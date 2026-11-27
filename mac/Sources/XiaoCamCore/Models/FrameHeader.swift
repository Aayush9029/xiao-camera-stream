import Foundation

public struct FrameHeader: Codable, Equatable, Sendable {
    public static let size = 28
    public static let magic: UInt32 = 0x5254_5358
    public static let payloadLimits = 64...(1 << 20)

    public var sequence: UInt32
    public var deviceMicroseconds: UInt64
    public var width: UInt16
    public var height: UInt16
    public var modeValue: UInt8
    public var quality: UInt8
    public var temperatureTenths: Int16
    public var payloadLength: UInt32

    public init(
        sequence: UInt32,
        deviceMicroseconds: UInt64,
        width: UInt16,
        height: UInt16,
        modeValue: UInt8,
        quality: UInt8,
        temperatureTenths: Int16,
        payloadLength: UInt32
    ) {
        self.sequence = sequence
        self.deviceMicroseconds = deviceMicroseconds
        self.width = width
        self.height = height
        self.modeValue = modeValue
        self.quality = quality
        self.temperatureTenths = temperatureTenths
        self.payloadLength = payloadLength
    }

    public init?(_ bytes: Data) {
        guard bytes.count >= Self.size else { return nil }
        let header = bytes.prefix(Self.size).withUnsafeBytes { raw -> FrameHeader? in
            func read<T: FixedWidthInteger>(_ offset: Int, as type: T.Type) -> T {
                T(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: T.self))
            }
            guard read(0, as: UInt32.self) == Self.magic else { return nil }
            return FrameHeader(
                sequence: read(4, as: UInt32.self),
                deviceMicroseconds: read(8, as: UInt64.self),
                width: read(16, as: UInt16.self),
                height: read(18, as: UInt16.self),
                modeValue: read(20, as: UInt8.self),
                quality: read(21, as: UInt8.self),
                temperatureTenths: read(22, as: Int16.self),
                payloadLength: read(24, as: UInt32.self)
            )
        }
        guard let header else { return nil }
        self = header
    }

    public var mode: CameraMode? { CameraMode(headerValue: modeValue) }

    public var temperatureC: Double { Double(temperatureTenths) / 10 }

    public var hasValidPayloadLength: Bool {
        Self.payloadLimits.contains(Int(payloadLength))
    }

    public func encoded() -> Data {
        var data = Data(capacity: Self.size)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append(Self.magic)
        append(sequence)
        append(deviceMicroseconds)
        append(width)
        append(height)
        append(modeValue)
        append(quality)
        append(temperatureTenths)
        append(payloadLength)
        return data
    }
}
