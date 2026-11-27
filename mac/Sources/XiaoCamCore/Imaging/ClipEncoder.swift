import Foundation

public enum ClipEncoder {
    public struct Input: Sendable {
        public var jpeg: Data
        public var time: Double
        public var label: String?

        public init(jpeg: Data, time: Double, label: String?) {
            self.jpeg = jpeg
            self.time = time
            self.label = label
        }
    }

    public struct Output: Equatable, Sendable {
        public var data: Data
        public var width: Int
        public var height: Int
        public var frameCount: Int
    }

    public static func encode(_ frames: [Input], enhance: Bool, bitRate: Int = 4_000_000) async throws -> Output {
        guard let first = frames.first else { throw ImagingError.noFrames }
        let writer = ClipWriter(enhance: enhance, bitRate: bitRate)
        for frame in frames {
            try await writer.append(jpeg: frame.jpeg, time: frame.time - first.time, label: frame.label)
        }
        return try await writer.finish()
    }
}
