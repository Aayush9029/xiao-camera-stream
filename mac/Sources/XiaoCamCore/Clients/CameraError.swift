import Foundation

public enum CameraError: Error, Equatable, LocalizedError, Sendable {
    case unreachable(host: String, reason: String)
    case timedOut(host: String)
    case busy(String)
    case httpStatus(Int, String)
    case invalidResponse(String)
    case notACamera(host: String)
    case streamClosed
    case streamStalled

    public var errorDescription: String? {
        switch self {
        case let .unreachable(host, reason):
            "Camera at \(host) is unreachable: \(reason)"
        case let .timedOut(host):
            "Camera at \(host) did not answer in time."
        case let .busy(message):
            "Camera is busy: \(message)"
        case let .httpStatus(code, message):
            message.isEmpty ? "Camera returned HTTP \(code)." : "Camera returned HTTP \(code): \(message)"
        case let .invalidResponse(message):
            "Camera sent an invalid response: \(message)"
        case let .notACamera(host):
            "\(host) answered, but it is not a XIAO camera."
        case .streamClosed:
            "The camera closed the stream."
        case .streamStalled:
            "The camera stream stopped sending frames."
        }
    }
}
