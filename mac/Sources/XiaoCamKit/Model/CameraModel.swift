import CoreGraphics
import Dependencies
import Foundation
import IssueReporting
import Observation
import OSLog
import Sharing

@MainActor
@Observable
public final class CameraModel {
    public static let pollInterval: Duration = .seconds(2)
    public static let liveWaitTimeout: Duration = .seconds(10)

    private static let logger = Logger(subsystem: "art.aayush.xiaocam", category: "CameraModel")

    public private(set) var connectionState: ConnectionState = .searching
    public private(set) var status: DeviceStatus?
    public private(set) var preview: CGImage?
    public private(set) var hasPreview = false
    public private(set) var receiveFPS: Double = 0
    public private(set) var isStreaming = false
    public private(set) var cameras: [DiscoveredCamera] = []
    public private(set) var isScanning = false
    public private(set) var photoCapture: PhotoCaptureState = .idle
    public private(set) var commandError: String?

    @ObservationIgnored @Shared(.savedHost) public var savedHost
    @ObservationIgnored @Shared(.enhanceImage) public var enhanceImage
    @ObservationIgnored @Shared(.timestampOverlay) public var timestampOverlay

    @ObservationIgnored public let jobs: CaptureJobs
    @ObservationIgnored public let access = CameraAccess()

    @ObservationIgnored @Dependency(\.cameraClient) private var client
    @ObservationIgnored @Dependency(\.discoveryClient) private var discovery
    @ObservationIgnored @Dependency(\.photoLibrary) private var photoLibrary
    @ObservationIgnored @Dependency(\.continuousClock) private var clock
    @ObservationIgnored @Dependency(\.date.now) private var now

    @ObservationIgnored private var liveHost: String?
    @ObservationIgnored private var pendingHandoff: String?
    @ObservationIgnored private var streamDemand = 0
    @ObservationIgnored private var streamHost: String?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [Int: AsyncStream<Frame>.Continuation] = [:]
    @ObservationIgnored private var nextSubscriberID = 0
    @ObservationIgnored private var fpsMeter = FPSMeter()
    @ObservationIgnored private var lastFPSUpdate = Date.distantPast
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let wake = WakeSignal()

    public init() {
        let reference = ModelReference()
        jobs = CaptureJobs(source: .model(reference), access: access)
        reference.model = self
    }

    public var currentStreamDemand: Int { streamDemand }

    public var appStatus: AppStatus {
        AppStatus(
            connection: connectionState,
            device: status,
            receiveFPS: receiveFPS,
            isStreaming: isStreaming,
            savedHost: savedHost,
            enhanceImage: enhanceImage,
            timestampOverlay: timestampOverlay
        )
    }

    public func task() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        var failures = 0
        while !Task.isCancelled {
            var host = takeHandoff()
            if host == nil { host = await locateCamera() }
            if let handoff = takeHandoff() { host = handoff }
            if let host {
                failures = 0
                if await monitor(host) { continue }
            }
            guard !Task.isCancelled else { break }
            failures += 1
            await sleepOrWake(for: Self.retryDelay(afterFailures: failures))
        }
    }

    public static func retryDelay(afterFailures failures: Int) -> Duration {
        .seconds(min(30, 1 << min(max(failures - 1, 0), 5)))
    }

    // MARK: - Actions

    public func connectButtonTapped(host: String) async {
        do {
            _ = try await connect(to: host)
            commandError = nil
        } catch {
            commandError = error.message
        }
    }

    public func rescanButtonTapped() async {
        _ = await scan()
        if liveHost == nil { wake.signal() }
    }

    public func modeSelected(_ mode: CameraMode) async {
        do {
            _ = try await setMode(mode)
            commandError = nil
        } catch {
            commandError = error.message
        }
    }

    public func settingChanged(_ setting: CameraSetting, to value: Int) async {
        status?.apply(CameraSettingValue(setting: setting, value: value))
        do {
            _ = try await updateSettings([setting.validate(value)])
            commandError = nil
        } catch {
            commandError = XiaoCamError(error).message
            _ = try? await refreshStatus()
        }
    }

    public func capturePhotoButtonTapped() async {
        guard !photoCapture.is(\.capturing) else { return }
        photoCapture = .capturing
        do {
            let result = try await jobs.run(.snap(SnapOptions()))
            let url = try await photoLibrary.save(result.data, now)
            photoCapture = .saved(url)
        } catch {
            photoCapture = .failed(XiaoCamError(error).message)
        }
    }

    public func enhanceImageToggled() {
        $enhanceImage.withLock { $0.toggle() }
    }

    public func timestampOverlayToggled() {
        $timestampOverlay.withLock { $0.toggle() }
    }

    // MARK: - Commands

    public func connect(to host: String) async throws(XiaoCamError) -> DeviceStatus {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw XiaoCamError(.badRequest, "Give a host name or an IP address.") }
        let status: DeviceStatus
        do {
            status = try await client.status(host: host)
        } catch {
            throw XiaoCamError(error)
        }
        $savedHost.withLock { $0 = host }
        self.status = status
        if liveHost != host {
            pendingHandoff = host
            setLiveHost(host)
            wake.signal()
        }
        return status
    }

    public func discover() async -> [DiscoveredCamera] {
        await scan()
    }

    public func setMode(_ mode: CameraMode) async throws(XiaoCamError) -> DeviceStatus {
        let host = try await requireLiveHost()
        let client = client
        do {
            let status = try await access.shared { try await client.setMode(host: host, mode: mode) }
            guard liveHost == host else { return status }
            self.status = status
            return status
        } catch {
            throw XiaoCamError(error)
        }
    }

    public func updateSettings(_ values: [CameraSettingValue]) async throws(XiaoCamError) -> DeviceStatus {
        let host = try await requireLiveHost()
        let client = client
        do {
            let status = try await access.shared { try await client.updateSettings(host: host, values: values) }
            guard liveHost == host else { return status }
            self.status = status
            return status
        } catch {
            throw XiaoCamError(error)
        }
    }

    public func refreshStatus() async throws(XiaoCamError) -> DeviceStatus {
        let host = try await requireLiveHost()
        do {
            let status = try await client.status(host: host)
            self.status = status
            return status
        } catch {
            throw XiaoCamError(error)
        }
    }

    public func waitUntilSettled(timeout: Duration = .seconds(8)) async {
        var waited = Duration.zero
        while !connectionState.is(\.live), !connectionState.is(\.offline), waited < timeout {
            try? await clock.sleep(for: .milliseconds(200))
            waited += .milliseconds(200)
        }
    }

    func waitForLiveHost(timeout: Duration = liveWaitTimeout) async throws(XiaoCamError) -> String {
        var waited = Duration.zero
        while true {
            if let liveHost { return liveHost }
            guard waited < timeout else { throw XiaoCamError.cameraOffline(offlineReason) }
            do {
                try await clock.sleep(for: .milliseconds(200))
            } catch {
                throw XiaoCamError(error)
            }
            waited += .milliseconds(200)
        }
    }

    func deviceStatusChanged(_ status: DeviceStatus) {
        self.status = status
    }

    private func requireLiveHost() async throws(XiaoCamError) -> String {
        try await waitForLiveHost()
    }

    private var offlineReason: String {
        switch connectionState {
        case let .offline(reason): reason
        case .searching: "XiaoCam is still looking for the camera."
        case let .connecting(host): "no answer from \(host) yet."
        case let .live(host): "the connection to \(host) dropped."
        }
    }

    // MARK: - Streaming

    public func addStreamDemand() {
        streamDemand += 1
        updateStream()
    }

    public func removeStreamDemand() {
        guard streamDemand > 0 else {
            reportIssue("removeStreamDemand() was called more often than addStreamDemand().")
            return
        }
        streamDemand -= 1
        updateStream()
    }

    public func streamWhileVisible() async {
        addStreamDemand()
        defer { removeStreamDemand() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(86_400))
        }
    }

    public func frameSubscription() -> AsyncStream<Frame> {
        let (stream, continuation) = AsyncStream.makeStream(of: Frame.self, bufferingPolicy: .bufferingNewest(8))
        let id = nextSubscriberID
        nextSubscriberID += 1
        subscribers[id] = continuation
        addStreamDemand()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.endSubscription(id) }
        }
        return stream
    }

    private func endSubscription(_ id: Int) {
        guard subscribers.removeValue(forKey: id) != nil else { return }
        removeStreamDemand()
    }

    private func updateStream() {
        let target = streamDemand > 0 ? liveHost : nil
        guard target != streamHost else { return }
        streamTask?.cancel()
        streamTask = nil
        streamHost = target
        isStreaming = false
        receiveFPS = 0
        fpsMeter.reset()
        guard let target else { return }
        streamTask = Task { [weak self] in
            await self?.runStream(host: target)
        }
    }

    private func runStream(host: String) async {
        var failures = 0
        while !Task.isCancelled {
            do {
                for try await frame in client.frames(host: host) {
                    failures = 0
                    await receive(frame)
                }
            } catch {
                Self.logger.info("Stream from \(host, privacy: .public) ended: \(error.localizedDescription, privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            isStreaming = false
            failures += 1
            try? await clock.sleep(for: .milliseconds(min(5000, 250 << min(failures, 5))))
        }
    }

    private func receive(_ frame: Frame) async {
        for continuation in subscribers.values {
            continuation.yield(frame)
        }
        let image = await Self.decodePreview(frame.jpeg)
        guard !Task.isCancelled, streamHost != nil else { return }
        isStreaming = true
        if let image {
            preview = image
            if !hasPreview { hasPreview = true }
        }
        fpsMeter.record(frame.receivedAt.timeIntervalSinceReferenceDate)
        if frame.receivedAt.timeIntervalSince(lastFPSUpdate) >= 0.5 || receiveFPS == 0 {
            receiveFPS = fpsMeter.framesPerSecond
            lastFPSUpdate = frame.receivedAt
        }
    }

    @concurrent
    private nonisolated static func decodePreview(_ jpeg: Data) async -> CGImage? {
        JPEGCodec.thumbnail(jpeg, maxPixelSize: 1280)
    }

    // MARK: - Connection

    private func takeHandoff() -> String? {
        defer { pendingHandoff = nil }
        return pendingHandoff
    }

    private var isSearchUnclaimed: Bool { liveHost == nil && pendingHandoff == nil }

    private func locateCamera() async -> String? {
        if let host = savedHost, !host.isEmpty {
            if isSearchUnclaimed { connectionState = .connecting(host: host) }
            if let status = try? await client.status(host: host), isSearchUnclaimed {
                self.status = status
                return host
            }
        }
        guard !Task.isCancelled, isSearchUnclaimed else { return nil }
        connectionState = .searching
        let found = await scan()
        guard isSearchUnclaimed else { return nil }
        guard let camera = found.first else {
            connectionState = .offline(reason: "No camera found on this network.")
            return nil
        }
        status = camera.status
        $savedHost.withLock { $0 = camera.host }
        return camera.host
    }

    private func monitor(_ host: String) async -> Bool {
        setLiveHost(host)
        defer { if liveHost == host { setLiveHost(nil) } }
        var misses = 0
        while !Task.isCancelled {
            await sleepOrWake(for: Self.pollInterval)
            guard liveHost == host, pendingHandoff == nil else { return true }
            do {
                let status = try await client.status(host: host)
                guard liveHost == host else { return true }
                self.status = status
                misses = 0
            } catch is CancellationError {
                return false
            } catch {
                guard liveHost == host else { return true }
                misses += 1
                if misses >= 2 {
                    connectionState = .offline(reason: error.localizedDescription)
                    return false
                }
            }
        }
        return false
    }

    private func setLiveHost(_ host: String?) {
        if host != liveHost {
            preview = nil
            hasPreview = false
        }
        liveHost = host
        if let host { connectionState = .live(host: host) }
        updateStream()
    }

    private func scan() async -> [DiscoveredCamera] {
        isScanning = true
        defer { isScanning = false }
        let found = await discovery.discover(savedHost: savedHost)
        cameras = found
        return found
    }

    private func sleepOrWake(for duration: Duration) async {
        let clock = clock
        let wake = wake
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await clock.sleep(for: duration) }
            group.addTask { await wake.wait() }
            await group.next()
            group.cancelAll()
        }
    }
}
