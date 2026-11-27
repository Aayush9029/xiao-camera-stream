import Foundation

public struct FrameStreamParser: Sendable {
    public struct Packet: Equatable, Sendable {
        public var header: FrameHeader
        public var jpeg: Data
    }

    public static let maximumBufferedBytes = 4 << 20

    public private(set) var discardedBytes = 0
    private var buffer = Data()

    private static let magicBytes = withUnsafeBytes(of: FrameHeader.magic.littleEndian) { Data($0) }

    public init() {}

    public var bufferedByteCount: Int { buffer.count }

    public mutating func append(_ data: Data) {
        buffer.append(data)
        if buffer.count > Self.maximumBufferedBytes {
            discard(buffer.count - Self.maximumBufferedBytes)
        }
    }

    public mutating func nextPacket() -> Packet? {
        while buffer.count >= Self.magicBytes.count {
            guard buffer.starts(with: Self.magicBytes) else {
                resynchronize()
                continue
            }
            guard buffer.count >= FrameHeader.size else { return nil }
            guard let header = FrameHeader(buffer), header.hasValidPayloadLength else {
                discard(1)
                continue
            }
            let total = FrameHeader.size + Int(header.payloadLength)
            guard buffer.count >= total else { return nil }
            let start = buffer.startIndex
            let jpeg = Data(buffer[(start + FrameHeader.size)..<(start + total)])
            guard jpeg.starts(with: [0xFF, 0xD8]) else {
                discard(1)
                continue
            }
            buffer.removeSubrange(start..<(start + total))
            return Packet(header: header, jpeg: jpeg)
        }
        return nil
    }

    private mutating func resynchronize() {
        let searchStart = buffer.index(after: buffer.startIndex)
        if let range = buffer.range(of: Self.magicBytes, in: searchStart..<buffer.endIndex) {
            discard(buffer.distance(from: buffer.startIndex, to: range.lowerBound))
        } else {
            discard(buffer.count - (Self.magicBytes.count - 1))
        }
    }

    private mutating func discard(_ count: Int) {
        guard count > 0 else { return }
        let start = buffer.startIndex
        buffer.removeSubrange(start..<(start + count))
        discardedBytes += count
    }
}
