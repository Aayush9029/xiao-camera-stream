import Clocks
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import XiaoCamKit

@MainActor
@Suite(.serialized)
struct CameraModelTests {
    @Test func connectsToTheSavedHostAndPollsTheStatus() async {
        let clock = TestClock()
        let hosts = LockIsolated<[String]>([])
        let model = withDependencies {
            $0.continuousClock = clock
            $0.cameraClient.status = { host in
                hosts.withValue { $0.append(host) }
                return .preview
            }
            $0.discoveryClient.discover = { _ in [] }
        } operation: {
            CameraModel()
        }
        model.$savedHost.withLock { $0 = "10.0.0.5" }

        let task = Task { await model.task() }
        await eventually { model.connectionState == .live(host: "10.0.0.5") }
        #expect(model.status == .preview)

        let waited = await advance(clock, until: { hosts.value.count == 2 })
        #expect(waited >= CameraModel.pollInterval)
        #expect(hosts.value == ["10.0.0.5", "10.0.0.5"])

        task.cancel()
        await task.value
    }

    @Test func retriesWithABackoffUntilDiscoveryFindsTheCamera() async {
        let clock = TestClock()
        let reachable = LockIsolated(false)
        let scans = LockIsolated(0)
        let model = withDependencies {
            $0.continuousClock = clock
            $0.cameraClient.status = { host in
                guard reachable.value else { throw CameraError.timedOut(host: host) }
                return .preview
            }
            $0.discoveryClient.discover = { _ in
                scans.withValue { $0 += 1 }
                return reachable.value ? [DiscoveredCamera(host: "192.168.2.106", source: .bonjour, status: .preview)] : []
            }
        } operation: {
            CameraModel()
        }

        let task = Task { await model.task() }
        await eventually { model.connectionState == .offline(reason: "No camera found on this network.") }
        #expect(scans.value == 1)

        reachable.setValue(true)
        let waited = await advance(clock, until: { model.connectionState == .live(host: "192.168.2.106") })
        #expect(waited >= CameraModel.retryDelay(afterFailures: 1))
        #expect(scans.value == 2)
        #expect(model.savedHost == "192.168.2.106")

        task.cancel()
        await task.value
    }

    @Test func goesOfflineAfterTwoMissedPolls() async {
        let clock = TestClock()
        let answering = LockIsolated(true)
        let calls = LockIsolated(0)
        let model = withDependencies {
            $0.continuousClock = clock
            $0.cameraClient.status = { host in
                calls.withValue { $0 += 1 }
                guard answering.value else { throw CameraError.timedOut(host: host) }
                return .preview
            }
            $0.discoveryClient.discover = { _ in [] }
        } operation: {
            CameraModel()
        }
        model.$savedHost.withLock { $0 = "10.0.0.5" }

        let task = Task { await model.task() }
        await eventually { model.connectionState == .live(host: "10.0.0.5") }

        answering.setValue(false)
        await advance(clock, until: { calls.value == 2 })
        #expect(model.connectionState == .live(host: "10.0.0.5"))

        await advance(clock, until: { model.connectionState.is(\.offline) })
        #expect(calls.value == 3)
        #expect(model.connectionState == .offline(reason: CameraError.timedOut(host: "10.0.0.5").localizedDescription))

        task.cancel()
        await task.value
    }

    @Test func streamsOnlyWhileSomethingNeedsFrames() async throws {
        let clock = TestClock()
        let feeds = LockIsolated<[AsyncThrowingStream<Frame, any Error>.Continuation]>([])
        let closed = LockIsolated(0)
        let model = withDependencies {
            $0.continuousClock = clock
            $0.cameraClient.status = { _ in .preview }
            $0.discoveryClient.discover = { _ in [] }
            $0.cameraClient.frames = { _ in
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Frame.self)
                continuation.onTermination = { _ in closed.withValue { $0 += 1 } }
                feeds.withValue { $0.append(continuation) }
                return stream
            }
        } operation: {
            CameraModel()
        }
        model.$savedHost.withLock { $0 = "10.0.0.5" }

        let task = Task { await model.task() }
        await eventually { model.connectionState.is(\.live) }
        #expect(feeds.value.isEmpty)

        model.addStreamDemand()
        await eventually { feeds.value.count == 1 }
        let jpeg = try Fixtures.jpeg(width: 320, height: 240)
        for index in 0..<5 {
            feeds.value[0].yield(Fixtures.frame(
                jpeg: jpeg,
                sequence: UInt32(index),
                micros: UInt64(index) * 100_000,
                receivedAt: Date(timeIntervalSinceReferenceDate: Double(index) / 10)
            ))
        }
        await eventually { model.hasPreview && model.receiveFPS > 0 }
        #expect(model.isStreaming)
        #expect(model.preview?.width == 320)
        #expect(abs(model.receiveFPS - 10) < 0.01)

        model.removeStreamDemand()
        await eventually { closed.value == 1 }
        #expect(!model.isStreaming)
        #expect(model.receiveFPS == 0)
        #expect(feeds.value.count == 1)

        task.cancel()
        await task.value
    }

    @Test func aFrameSubscriptionHoldsTheStreamOpen() async throws {
        let clock = TestClock()
        let feeds = LockIsolated<[AsyncThrowingStream<Frame, any Error>.Continuation]>([])
        let closed = LockIsolated(0)
        let model = withDependencies {
            $0.continuousClock = clock
            $0.cameraClient.status = { _ in .preview }
            $0.discoveryClient.discover = { _ in [] }
            $0.cameraClient.frames = { _ in
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Frame.self)
                continuation.onTermination = { _ in closed.withValue { $0 += 1 } }
                feeds.withValue { $0.append(continuation) }
                return stream
            }
        } operation: {
            CameraModel()
        }
        model.$savedHost.withLock { $0 = "10.0.0.5" }
        let task = Task { await model.task() }
        await eventually { model.connectionState.is(\.live) }

        let subscription = Task { () -> UInt32? in
            for await frame in model.frameSubscription() { return frame.header.sequence }
            return nil
        }
        await eventually { model.currentStreamDemand == 1 && feeds.value.count == 1 }
        let jpeg = try Fixtures.jpeg(width: 32, height: 24)
        feeds.value[0].yield(Fixtures.frame(jpeg: jpeg, sequence: 42, micros: 0, receivedAt: .now))
        #expect(await subscription.value == 42)
        await eventually { model.currentStreamDemand == 0 && closed.value == 1 }

        task.cancel()
        await task.value
    }

    @Test func capturePhotoSavesATimestampedSnap() async throws {
        let clock = TestClock()
        let jpeg = try Fixtures.jpeg(width: 640, height: 480)
        let saved = LockIsolated<[Data]>([])
        let model = withDependencies {
            $0.continuousClock = clock
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.uuid = .incrementing
            $0.cameraClient.status = { _ in .preview }
            $0.cameraClient.capture = { _ in jpeg }
            $0.discoveryClient.discover = { _ in [] }
            $0.photoLibrary.save = { data, _ in
                saved.withValue { $0.append(data) }
                return URL(filePath: "/tmp/XiaoCam 1.jpg")
            }
        } operation: {
            CameraModel()
        }
        model.$savedHost.withLock { $0 = "10.0.0.5" }
        let task = Task { await model.task() }
        await eventually { model.connectionState.is(\.live) }

        await model.capturePhotoButtonTapped()
        #expect(model.photoCapture == .saved(URL(filePath: "/tmp/XiaoCam 1.jpg")))
        #expect(saved.value.count == 1)
        #expect(saved.value.first != jpeg)
        #expect(JPEGCodec.size(of: saved.value[0])?.width == 640)

        task.cancel()
        await task.value
    }

    @Test func connectSwitchesTheLiveHostBeforeItReturns() async throws {
        let clock = TestClock()
        let polled = LockIsolated<[String]>([])
        let modeHosts = LockIsolated<[String]>([])
        let model = withDependencies {
            $0.continuousClock = clock
            $0.cameraClient.status = { host in
                polled.withValue { $0.append(host) }
                return .preview
            }
            $0.cameraClient.setMode = { host, mode in
                modeHosts.withValue { $0.append(host) }
                return Fixtures.status(mode: mode)
            }
            $0.discoveryClient.discover = { _ in [] }
        } operation: {
            CameraModel()
        }
        model.$savedHost.withLock { $0 = "10.0.0.5" }
        let task = Task { await model.task() }
        await eventually { model.connectionState == .live(host: "10.0.0.5") }

        _ = try await model.connect(to: "10.0.0.9")
        #expect(model.connectionState == .live(host: "10.0.0.9"))
        _ = try await model.setMode(.quality)
        #expect(modeHosts.value == ["10.0.0.9"])

        let afterConnect = polled.value.count
        await advance(clock, until: { polled.value.count > afterConnect })
        #expect(polled.value.dropFirst(afterConnect).allSatisfy { $0 == "10.0.0.9" })
        #expect(model.connectionState == .live(host: "10.0.0.9"))
        #expect(model.savedHost == "10.0.0.9")

        task.cancel()
        await task.value
    }

    @Test func connectSavesTheHostAndRejectsAnUnreachableOne() async {
        let model = withDependencies {
            $0.cameraClient.status = { host in
                guard host == "10.0.0.9" else { throw CameraError.timedOut(host: host) }
                return .preview
            }
        } operation: {
            CameraModel()
        }

        await #expect(throws: XiaoCamError(.cameraOffline, "camera offline: Camera at 10.0.0.1 did not answer in time.")) {
            try await model.connect(to: "10.0.0.1")
        }
        #expect(model.savedHost == nil)

        let status = try? await model.connect(to: " 10.0.0.9 ")
        #expect(status == .preview)
        #expect(model.savedHost == "10.0.0.9")
    }
}
