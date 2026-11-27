import Foundation

public struct XiaoCamError: Error, Codable, Equatable, LocalizedError, Sendable {
    public enum Code: String, Codable, Sendable {
        case appNotRunning
        case connectionLost
        case cameraOffline
        case badRequest
        case notFound
        case busy
        case failed
    }

    public var code: Code
    public var message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }

    public init(_ error: any Error) {
        switch error {
        case let error as XiaoCamError:
            self = error
        case let error as CameraError:
            switch error {
            case .unreachable, .timedOut, .streamClosed, .streamStalled:
                self.init(.cameraOffline, "camera offline: \(error.localizedDescription)")
            case .notACamera:
                self.init(.cameraOffline, "not a camera: \(error.localizedDescription)")
            case .busy:
                self.init(.busy, error.localizedDescription)
            case .httpStatus, .invalidResponse:
                self.init(.failed, error.localizedDescription)
            }
        case let error as CameraSettingError:
            self.init(.badRequest, error.localizedDescription)
        case is CancellationError:
            self.init(.failed, "The capture was cancelled.")
        default:
            self.init(.failed, error.localizedDescription)
        }
    }

    public static func cameraOffline(_ reason: String) -> Self {
        Self(.cameraOffline, "camera offline: \(reason)")
    }
}
