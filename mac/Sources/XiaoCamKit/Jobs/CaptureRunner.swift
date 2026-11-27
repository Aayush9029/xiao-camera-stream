import Dependencies
import Foundation
import OSLog

struct CaptureRunner: Sendable {
    typealias Progress = @Sendable (Double) async -> Void

    static let profileSettings: [CameraSetting] = [
        .quality, .brightness, .contrast, .saturation, .sharpness, .denoise,
        .aeLevel, .aec2, .gainCeiling, .nightMode, .hmirror, .vflip,
    ]
    static let modeSettleTime: Duration = .seconds(1)
    static let clipGraceTime: Double = 8

    private static let logger = Logger(subsystem: "art.aayush.xiaocam", category: "CaptureRunner")

    let source: CaptureSource
    let access: CameraAccess
    @Dependency(\.cameraClient) private var camera
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.date.now) private var now

    init(source: CaptureSource, access: CameraAccess) {
        self.source = source
        self.access = access
    }

    func run(_ request: CaptureRequest, progress: @escaping Progress) async throws -> CaptureResult {
        switch request {
        case let .snap(options): try await snap(options)
        case let .grid(options): try await grid(options, progress: progress)
        case let .clip(options): try await clip(options, progress: progress)
        }
    }

    private func snap(_ options: SnapOptions) async throws -> CaptureResult {
        let host = try await source.liveHost()
        let defaults = await source.defaults()
        let enhance = options.enhance ?? defaults.enhance
        let timestamp = options.timestamp ?? defaults.timestamp
        let jpeg: Data
        let mode: String?
        if let requested = options.mode {
            jpeg = try await withTemporaryMode(requested, host: host) { try await captureWithRetry(host: host) }
            mode = requested.rawValue
        } else {
            jpeg = try await access.shared { try await captureWithRetry(host: host) }
            mode = await source.status()?.mode
        }
        let capturedAt = now
        let label = timestamp ? FrameLabel(date: capturedAt).text() : nil
        let image = try await Self.process(jpeg: jpeg, enhance: enhance, label: label)
        return CaptureResult(
            kind: .snap,
            data: image.data,
            fileExtension: "jpg",
            width: image.width,
            height: image.height,
            mode: mode,
            enhanced: enhance,
            timestamped: timestamp,
            frames: [CaptureFrameInfo(index: 1, capturedAt: capturedAt, offset: 0)]
        )
    }

    private func grid(_ options: GridOptions, progress: Progress) async throws -> CaptureResult {
        let host = try await source.liveHost()
        let defaults = await source.defaults()
        let enhance = options.enhance ?? defaults.enhance
        let timestamp = options.timestamp ?? defaults.timestamp
        let plan = CapturePlan(every: options.every, for: options.duration)
        let clock: any Clock<Duration> = clock
        let shots = try await captureShots(plan: plan, host: host, clock: clock, progress: progress)
        let first = shots[0].capturedAt
        let frames = shots.enumerated().map { index, shot in
            CaptureFrameInfo(index: index + 1, capturedAt: shot.capturedAt, offset: shot.capturedAt.timeIntervalSince(first))
        }
        let labels = timestamp
            ? frames.map { FrameLabel(date: $0.capturedAt, index: $0.index, elapsed: $0.offset, style: .time).text() }
            : nil
        let layout = GridLayout(count: shots.count, columns: options.columns)
        let image = try await Self.composeGrid(shots.map(\.jpeg), labels: labels, layout: layout, enhance: enhance)
        return CaptureResult(
            kind: .grid,
            data: image.data,
            fileExtension: "jpg",
            width: image.width,
            height: image.height,
            mode: await source.status()?.mode,
            enhanced: enhance,
            timestamped: timestamp,
            frames: frames,
            interval: plan.interval,
            duration: plan.duration,
            columns: layout.columns,
            rows: layout.rows
        )
    }

    private func clip(_ options: ClipOptions, progress: @escaping Progress) async throws -> CaptureResult {
        _ = try await source.liveHost()
        let defaults = await source.defaults()
        let enhance = options.enhance ?? defaults.enhance
        let timestamp = options.timestamp ?? defaults.timestamp
        let plan = ClipPlan(for: options.duration, fps: options.fps)
        let recording = try await access.shared {
            try await record(plan: plan, enhance: enhance, timestamp: timestamp, progress: progress)
        }
        return CaptureResult(
            kind: .clip,
            data: recording.output.data,
            fileExtension: "mp4",
            width: recording.output.width,
            height: recording.output.height,
            mode: recording.mode,
            enhanced: enhance,
            timestamped: timestamp,
            frames: recording.frames,
            duration: recording.duration,
            fps: recording.duration > 0 ? Double(recording.frames.count - 1) / recording.duration : nil
        )
    }

    private struct Shot: Sendable {
        var jpeg: Data
        var capturedAt: Date
    }

    private struct Recording: Sendable {
        var output: ClipEncoder.Output
        var frames: [CaptureFrameInfo]
        var duration: Double
        var mode: String?
    }

    private func captureShots<C: Clock<Duration>>(
        plan: CapturePlan,
        host: String,
        clock: C,
        progress: Progress
    ) async throws -> [Shot] {
        let start = clock.now
        var shots: [Shot] = []
        for (index, offset) in plan.offsets.enumerated() {
            try await clock.sleep(until: start.advanced(by: .seconds(offset)), tolerance: nil)
            let jpeg = try await access.shared { try await captureWithRetry(host: host) }
            shots.append(Shot(jpeg: jpeg, capturedAt: now))
            await progress(Double(index + 1) / Double(plan.frameCount))
        }
        return shots
    }

    private func record(plan: ClipPlan, enhance: Bool, timestamp: Bool, progress: @escaping Progress) async throws -> Recording {
        let frames = await source.frames()
        let clock = clock
        return try await withThrowingTaskGroup(of: Recording.self) { group in
            group.addTask {
                try await Self.encode(frames, plan: plan, enhance: enhance, timestamp: timestamp, progress: progress)
            }
            group.addTask {
                try await clock.sleep(for: .seconds(plan.duration + Self.clipGraceTime))
                throw CameraError.streamStalled
            }
            defer { group.cancelAll() }
            guard let recording = try await group.next() else { throw CameraError.streamStalled }
            return recording
        }
    }

    private static func encode(
        _ frames: AsyncStream<Frame>,
        plan: ClipPlan,
        enhance: Bool,
        timestamp: Bool,
        progress: Progress
    ) async throws -> Recording {
        let writer = ClipWriter(enhance: enhance)
        var start: UInt64?
        var lastKept: Double?
        var kept: [CaptureFrameInfo] = []
        var mode: String?
        var reachedEnd = false
        for await frame in frames {
            let micros = frame.header.deviceMicroseconds
            let first = start ?? micros
            start = first
            guard micros >= first else { break }
            let elapsed = Double(micros - first) / 1_000_000
            guard elapsed <= plan.duration else {
                reachedEnd = true
                break
            }
            if plan.accepts(elapsed: elapsed, sinceLastKept: lastKept) {
                let label = timestamp ? FrameLabel(date: frame.receivedAt, elapsed: elapsed).text() : nil
                try await writer.append(jpeg: frame.jpeg, time: elapsed, label: label)
                lastKept = elapsed
                kept.append(CaptureFrameInfo(index: kept.count + 1, capturedAt: frame.receivedAt, offset: elapsed))
                mode = mode ?? frame.header.mode?.rawValue ?? "custom"
            }
            await progress(min(elapsed / plan.duration, 1))
        }
        try Task.checkCancellation()
        guard reachedEnd, kept.count >= 2 else { throw CameraError.streamStalled }
        let output = try await writer.finish()
        return Recording(output: output, frames: kept, duration: kept.last?.offset ?? 0, mode: mode)
    }

    private func withTemporaryMode<T: Sendable>(
        _ mode: CameraMode,
        host: String,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        try await access.exclusive {
            let previous = try await camera.status(host: host)
            guard previous.cameraMode != mode else { return try await body() }
            let outcome: Result<T, any Error>
            do {
                let switched = try await retryingBusy { try await camera.setMode(host: host, mode: mode) }
                await source.statusChanged(switched)
                try await clock.sleep(for: Self.modeSettleTime)
                outcome = .success(try await body())
            } catch {
                outcome = .failure(error)
            }
            // A new task is not cancelled with this one, so the restore can finish its requests.
            await Task { await restore(previous, host: host) }.value
            return try outcome.get()
        }
    }

    private func restore(_ previous: DeviceStatus, host: String) async {
        do {
            var current = if let mode = previous.cameraMode {
                try await retryingBusy { try await camera.setMode(host: host, mode: mode) }
            } else {
                try await camera.status(host: host)
            }
            let isCustom = previous.cameraMode == nil
            let settings = isCustom ? [.framesize] + Self.profileSettings : Self.profileSettings
            let changed = settings
                .filter { ($0 == .framesize && isCustom) || current.value(for: $0) != previous.value(for: $0) }
                .map { CameraSettingValue(setting: $0, value: previous.value(for: $0)) }
            if !changed.isEmpty {
                current = try await retryingBusy { try await camera.updateSettings(host: host, values: changed) }
            }
            await source.statusChanged(current)
        } catch {
            Self.logger.error("Mode restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func captureWithRetry(host: String) async throws -> Data {
        do {
            return try await camera.capture(host: host)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await clock.sleep(for: .milliseconds(500))
            return try await camera.capture(host: host)
        }
    }

    private func retryingBusy<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch CameraError.busy {
            try await clock.sleep(for: .milliseconds(500))
            return try await operation()
        }
    }

    @concurrent
    private static func process(jpeg: Data, enhance: Bool, label: String?) async throws -> EncodedImage {
        try FrameProcessor.process(jpeg: jpeg, enhance: enhance, label: label)
    }

    @concurrent
    private static func composeGrid(_ jpegs: [Data], labels: [String]?, layout: GridLayout, enhance: Bool) async throws -> EncodedImage {
        guard let first = jpegs.first, let size = JPEGCodec.size(of: first) else { throw ImagingError.noFrames }
        let canvas = GridComposer.canvasSize(layout: layout, cellWidth: size.width, cellHeight: size.height)
        let maxPixelSize = max(canvas.cellWidth, canvas.cellHeight)
        var cells: [GridComposer.Cell] = []
        for (index, jpeg) in jpegs.enumerated() {
            try Task.checkCancellation()
            guard var image = JPEGCodec.thumbnail(jpeg, maxPixelSize: maxPixelSize) else { throw ImagingError.decodeFailed }
            if enhance { image = try ImageEnhancer.enhance(image) }
            cells.append(GridComposer.Cell(image: image, label: labels?[index]))
        }
        return try GridComposer.compose(cells, columns: layout.columns)
    }
}
