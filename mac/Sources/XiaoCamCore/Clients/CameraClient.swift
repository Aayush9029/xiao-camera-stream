import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct CameraClient: Sendable {
    public var status: @Sendable (_ host: String) async throws -> DeviceStatus
    public var setMode: @Sendable (_ host: String, _ mode: CameraMode) async throws -> DeviceStatus
    public var updateSettings: @Sendable (_ host: String, _ values: [CameraSettingValue]) async throws -> DeviceStatus
    public var capture: @Sendable (_ host: String) async throws -> Data
    public var frames: @Sendable (_ host: String) -> AsyncThrowingStream<Frame, any Error> = { _ in .finished() }
}

extension CameraClient: TestDependencyKey {
    public static var testValue: CameraClient { CameraClient() }
    public static var previewValue: CameraClient { .preview }
}

extension DependencyValues {
    public var cameraClient: CameraClient {
        get { self[CameraClient.self] }
        set { self[CameraClient.self] = newValue }
    }
}
