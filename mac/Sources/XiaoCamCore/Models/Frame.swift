import Foundation

public struct Frame: Equatable, Sendable {
    public var header: FrameHeader
    public var jpeg: Data
    public var receivedAt: Date

    public init(header: FrameHeader, jpeg: Data, receivedAt: Date) {
        self.header = header
        self.jpeg = jpeg
        self.receivedAt = receivedAt
    }
}
