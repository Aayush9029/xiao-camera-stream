import Clocks
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import XiaoCamKit

struct TemporaryModeTests {
    @Test func overlappingTemporaryModesEachCaptureInTheirOwnMode() async throws {
        var original = FakeCamera.preset(.balanced, from: .preview)
        original.brightness = 1
        let camera = FakeCamera(status: original, jpeg: try Fixtures.jpeg(width: 64, height: 48))
        let jobs = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient = camera.client
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        async let quality = jobs.run(.snap(SnapOptions(timestamp: false, mode: .quality)))
        async let performance = jobs.run(.snap(SnapOptions(timestamp: false, mode: .performance)))
        async let plain = jobs.run(.snap(SnapOptions(timestamp: false)))
        let results = try await [quality, performance, plain]

        #expect(results.map(\.mode) == ["quality", "performance", "balanced"])
        let state = camera.state.value
        #expect(state.capturedModes.sorted() == ["balanced", "performance", "quality"])
        #expect(state.status == original)
    }

    @Test func restoresACustomProfileThatHasTheSameFrameSize() async throws {
        var custom = FakeCamera.preset(.balanced, from: .preview)
        custom.mode = "custom"
        custom.brightness = 2
        let camera = FakeCamera(status: custom, jpeg: try Fixtures.jpeg(width: 64, height: 48))
        let jobs = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient = camera.client
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        _ = try await jobs.run(.snap(SnapOptions(timestamp: false, mode: .balanced)))

        let state = camera.state.value
        #expect(state.modeCalls == [.balanced])
        #expect(state.settingsCalls.last?.first == CameraSettingValue(setting: .framesize, value: 12))
        #expect(state.status == custom)
    }

    @Test func restoresTheModeWhenTheCaptureIsCancelled() async throws {
        let original = FakeCamera.preset(.balanced, from: .preview)
        let camera = FakeCamera(status: original, jpeg: try Fixtures.jpeg(width: 64, height: 48))
        let jobs = withDependencies {
            $0.continuousClock = TestClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
            $0.cameraClient = camera.client
        } operation: {
            CaptureJobs(source: Fixtures.source())
        }

        let job = try await jobs.start(.snap(SnapOptions(mode: .quality)))
        while camera.state.value.modeCalls.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        await jobs.cancelAll()

        await #expect(throws: XiaoCamError.self) { try await jobs.wait(for: job.id) }
        let state = camera.state.value
        #expect(state.modeCalls == [.quality, .balanced])
        #expect(state.capturedModes.isEmpty)
        #expect(state.status == original)
    }
}
