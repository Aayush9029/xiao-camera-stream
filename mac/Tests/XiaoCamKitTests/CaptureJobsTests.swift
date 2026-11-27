import Clocks
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import XiaoCamKit

struct CaptureJobsTests {
    @Test func snapBurnsInTheTimestampOnlyWhenAsked() async throws {
        let jpeg = try Fixtures.jpeg(width: 640, height: 480)
        let jobs = withDependencies {
            $0.cameraClient.capture = { _ in jpeg }
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.uuid = .incrementing
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        let labeled = try await jobs.run(.snap(SnapOptions()))
        #expect(labeled.kind == .snap)
        #expect(labeled.width == 640)
        #expect(labeled.height == 480)
        #expect(labeled.timestamped)
        #expect(labeled.data != jpeg)
        #expect(labeled.frames == [CaptureFrameInfo(index: 1, capturedAt: Date(timeIntervalSince1970: 1_795_000_000), offset: 0)])

        let raw = try await jobs.run(.snap(SnapOptions(timestamp: false)))
        #expect(raw.data == jpeg)
        #expect(!raw.timestamped)
    }

    @Test func snapInAnotherModeRestoresTheModeAndTheSettings() async throws {
        let jpeg = try Fixtures.jpeg(width: 64, height: 48)
        let modes = LockIsolated<[CameraMode]>([])
        let settings = LockIsolated<[[CameraSettingValue]]>([])
        let jobs = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient.status = { _ in Fixtures.status(mode: .balanced, brightness: 1) }
            $0.cameraClient.setMode = { _, mode in
                modes.withValue { $0.append(mode) }
                return Fixtures.status(mode: mode)
            }
            $0.cameraClient.updateSettings = { _, values in
                settings.withValue { $0.append(values) }
                return Fixtures.status(mode: .balanced, brightness: 1)
            }
            $0.cameraClient.capture = { _ in jpeg }
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        let result = try await jobs.run(.snap(SnapOptions(timestamp: false, mode: .quality)))
        #expect(result.mode == "quality")
        #expect(modes.value == [.quality, .balanced])
        #expect(settings.value == [[CameraSettingValue(setting: .brightness, value: 1)]])
    }

    @Test func gridTakesOnePhotoPerPlannedOffset() async throws {
        let jpeg = try Fixtures.jpeg(width: 1024, height: 768)
        let captures = LockIsolated(0)
        let jobs = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient.capture = { _ in
                captures.withValue { $0 += 1 }
                return jpeg
            }
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        let job = try await jobs.start(.grid(GridOptions(every: 2, duration: 8)))
        let finished = try await jobs.wait(for: job.id)
        #expect(captures.value == 5)
        #expect(finished.job.state == .done(fetched: true))
        #expect(finished.result.frames.count == 5)
        #expect(finished.result.columns == 3)
        #expect(finished.result.rows == 2)
        #expect(finished.result.interval == 2)
        #expect(finished.result.width == 2000)
        #expect(finished.result.height == 2 * 498 + 4)
    }

    @Test func clipKeepsFramesAtTheRequestedRate() async throws {
        let jpeg = try Fixtures.jpeg(width: 320, height: 240)
        let frames = (0..<60).map { index in
            Fixtures.frame(jpeg: jpeg, sequence: UInt32(index), micros: UInt64(index) * 50_000, receivedAt: .now)
        }
        let jobs = withDependencies {
            $0.continuousClock = TestClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
        } operation: {
            CaptureJobs(source: Fixtures.source(frames: {
                AsyncStream { continuation in
                    frames.forEach { continuation.yield($0) }
                    continuation.finish()
                }
            }))
        }

        let result = try await jobs.run(.clip(ClipOptions(duration: 2, fps: 10, timestamp: false)))
        #expect(result.kind == .clip)
        #expect(result.fileExtension == "mp4")
        #expect(result.frames.count == 21)
        #expect(result.frames.last?.offset == 2)
        #expect(result.width == 320)
        #expect(String(decoding: result.data[4..<8], as: UTF8.self) == "ftyp")
    }

    @Test func keepsTheLastEightResultsAndHandsEachOutOnce() async throws {
        let jpeg = try Fixtures.jpeg(width: 32, height: 24)
        let jobs = withDependencies {
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient.capture = { _ in jpeg }
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        var ids: [CaptureJob.ID] = []
        for _ in 0..<10 {
            let job = try await jobs.start(.snap(SnapOptions(timestamp: false)))
            ids.append(job.id)
            while await jobs.job(job.id)?.isFinished == false { await Task.yield() }
        }
        let listed = await jobs.list()
        #expect(listed.map(\.id) == Array(ids.suffix(CaptureJobs.retainedJobs)))
        #expect(await jobs.job(ids[0]) == nil)

        let first = try await jobs.take(ids[9])
        #expect(first.result.data == jpeg)
        await #expect(throws: XiaoCamError(.notFound, "The result of job \(ids[9]) was already fetched.")) {
            try await jobs.take(ids[9])
        }
    }

    @Test func aLongCaptureKeepsItsResultWhenNewerJobsFinishFirst() async throws {
        let jpeg = try Fixtures.jpeg(width: 64, height: 48)
        let gate = AsyncStream.makeStream(of: Void.self)
        let calls = LockIsolated(0)
        let jobs = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient.capture = { _ in
                let call = calls.withValue { count in
                    count += 1
                    return count
                }
                if call == 1 { for await _ in gate.stream { break } }
                return jpeg
            }
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        let grid = try await jobs.start(.grid(GridOptions(every: 1, duration: 0, timestamp: false)))
        while calls.value == 0 { try await Task.sleep(for: .milliseconds(2)) }
        for _ in 0..<CaptureJobs.retainedJobs {
            _ = try await jobs.run(.snap(SnapOptions(timestamp: false)))
        }
        gate.continuation.yield()

        let finished = try await jobs.wait(for: grid.id)
        #expect(finished.result.kind == .grid)
        #expect(finished.job.state == .done(fetched: true))
        #expect(await jobs.list().contains { $0.id == grid.id })
        #expect(await jobs.list().count == CaptureJobs.retainedJobs)
    }

    @Test func aClipThatStopsGettingFramesFailsAsStalled() async throws {
        let jpeg = try Fixtures.jpeg(width: 32, height: 24)
        let clock = TestClock()
        let feed = LockIsolated<AsyncStream<Frame>.Continuation?>(nil)
        let jobs = withDependencies {
            $0.continuousClock = clock
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
        } operation: {
            CaptureJobs(source: Fixtures.source(frames: {
                let (stream, continuation) = AsyncStream.makeStream(of: Frame.self)
                continuation.yield(Fixtures.frame(jpeg: jpeg, sequence: 1, micros: 0, receivedAt: .now))
                continuation.yield(Fixtures.frame(jpeg: jpeg, sequence: 2, micros: 200_000, receivedAt: .now))
                feed.setValue(continuation)
                return stream
            }))
        }

        let job = try await jobs.start(.clip(ClipOptions(duration: 4, timestamp: false)))
        var advanced = Duration.zero
        while await jobs.job(job.id)?.isFinished == false, advanced < .seconds(60) {
            await clock.advance(by: .milliseconds(500))
            advanced += .milliseconds(500)
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(advanced >= .seconds(12))
        await #expect(throws: XiaoCamError(.cameraOffline, "camera offline: The camera stream stopped sending frames.")) {
            try await jobs.wait(for: job.id)
        }
        feed.value?.finish()
    }

    @Test func aClipFromAStreamThatEndsEarlyFailsAsStalled() async throws {
        let jpeg = try Fixtures.jpeg(width: 32, height: 24)
        let jobs = withDependencies {
            $0.continuousClock = TestClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
        } operation: {
            CaptureJobs(source: Fixtures.source(frames: {
                AsyncStream { continuation in
                    for index in 0..<5 {
                        continuation.yield(Fixtures.frame(jpeg: jpeg, sequence: UInt32(index), micros: UInt64(index) * 100_000, receivedAt: .now))
                    }
                    continuation.finish()
                }
            }))
        }

        await #expect(throws: XiaoCamError(.cameraOffline, "camera offline: The camera stream stopped sending frames.")) {
            try await jobs.run(.clip(ClipOptions(duration: 3, timestamp: false)))
        }
    }

    @Test func aFailedCaptureReportsTheCameraAsOffline() async {
        let jobs = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient.capture = { host in throw CameraError.unreachable(host: host, reason: "no route") }
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        await #expect(throws: XiaoCamError(.cameraOffline, "camera offline: Camera at 10.0.0.5 is unreachable: no route")) {
            try await jobs.run(.snap(SnapOptions()))
        }
    }
}
