import Foundation

public struct EncodedImage: Equatable, Sendable {
    public var data: Data
    public var width: Int
    public var height: Int

    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

public enum ImagingError: Error, Equatable, LocalizedError, Sendable {
    case decodeFailed
    case encodeFailed
    case noFrames
    case videoWriterFailed(String)

    public var errorDescription: String? {
        switch self {
        case .decodeFailed: "The camera image could not be decoded."
        case .encodeFailed: "The image could not be encoded."
        case .noFrames: "No frames were captured."
        case let .videoWriterFailed(reason): "The video could not be written: \(reason)"
        }
    }
}
