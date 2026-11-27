import Foundation

public struct LineBuffer: Sendable {
    public static let maximumLineBytes = 64 << 20

    public let limit: Int
    private var buffer = Data()
    private var scannedCount = 0

    public init(limit: Int = maximumLineBytes) {
        self.limit = limit
    }

    public var isOverflowing: Bool { buffer.count > limit }

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    public mutating func nextLine() -> Data? {
        let start = buffer.startIndex
        guard let newline = buffer[(start + scannedCount)...].firstIndex(of: 0x0A) else {
            scannedCount = buffer.count
            return nil
        }
        let line = Data(buffer[start..<newline])
        buffer.removeSubrange(start...newline)
        scannedCount = 0
        return line
    }
}
