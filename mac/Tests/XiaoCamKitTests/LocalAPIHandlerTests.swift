import Clocks
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import XiaoCamKit

@MainActor
struct LocalAPIHandlerTests {
    @Test func pollingAFailedJobWithoutWaitingReportsItsError() async throws {
        let model = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 1_795_000_000)
        } operation: {
            CameraModel()
        }
        let handler = LocalAPIHandler(model: model)

        let started = await handler.handle(.capture(.grid(GridOptions(every: 1, duration: 2)), detach: true))
        let id = try #require(started.job?.id)
        while await model.jobs.job(id)?.isFinished == false { try await Task.sleep(for: .milliseconds(2)) }

        let polled = await handler.handle(.job(id: id.rawValue, wait: false))
        #expect(polled.error == XiaoCamError(.cameraOffline, "camera offline: XiaoCam is still looking for the camera."))
        #expect(polled.job == nil)
        let waited = await handler.handle(.job(id: id.rawValue, wait: true))
        #expect(waited.error == polled.error)
    }
}
