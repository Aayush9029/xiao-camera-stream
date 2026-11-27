import CustomDump
import Foundation
import Testing
@testable import XiaoCamCore

struct FrameStreamParserTests {
    @Test func decodesTheFirmwareHeaderLayout() throws {
        let header = FrameHeader(
            sequence: 0x0102_0304,
            deviceMicroseconds: 0x1122_3344_5566_7788,
            width: 1024,
            height: 768,
            modeValue: 2,
            quality: 12,
            temperatureTenths: -15,
            payloadLength: 4096
        )
        let bytes = header.encoded()
        #expect(bytes.count == 28)
        #expect(Array(bytes.prefix(4)) == Array("XSTR".utf8))
        #expect(Array(bytes[4..<8]) == [0x04, 0x03, 0x02, 0x01])

        let decoded = try #require(FrameHeader(bytes))
        expectNoDifference(decoded, header)
        #expect(decoded.mode == .quality)
        #expect(decoded.temperatureC == -1.5)
    }

    @Test func parsesAFrameThatArrivesOneByteAtATime() {
        let jpeg = Self.jpeg(size: 300, fill: 0x11)
        let stream = Self.packet(sequence: 7, jpeg: jpeg)
        var parser = FrameStreamParser()
        var packets: [FrameStreamParser.Packet] = []
        for byte in stream {
            parser.append(Data([byte]))
            while let packet = parser.nextPacket() { packets.append(packet) }
        }
        #expect(packets.map(\.header.sequence) == [7])
        #expect(packets.first?.jpeg == jpeg)
        #expect(parser.bufferedByteCount == 0)
        #expect(parser.discardedBytes == 0)
    }

    @Test func parsesSeveralFramesFromOneChunk() {
        var parser = FrameStreamParser()
        parser.append(Self.packet(sequence: 1, jpeg: Self.jpeg(size: 100, fill: 1))
            + Self.packet(sequence: 2, jpeg: Self.jpeg(size: 200, fill: 2))
            + Self.packet(sequence: 3, jpeg: Self.jpeg(size: 150, fill: 3)))
        var sequences: [UInt32] = []
        while let packet = parser.nextPacket() { sequences.append(packet.header.sequence) }
        #expect(sequences == [1, 2, 3])
    }

    @Test func resynchronizesAfterGarbage() {
        var parser = FrameStreamParser()
        let garbage = Data("noise XST XS".utf8)
        parser.append(garbage + Self.packet(sequence: 9, jpeg: Self.jpeg(size: 128, fill: 9)))
        let packet = parser.nextPacket()
        #expect(packet?.header.sequence == 9)
        #expect(parser.discardedBytes == garbage.count)
    }

    @Test func skipsAHeaderWithAnInsaneLength() {
        var parser = FrameStreamParser()
        var bad = FrameHeader(
            sequence: 1, deviceMicroseconds: 0, width: 1, height: 1,
            modeValue: 1, quality: 10, temperatureTenths: 0, payloadLength: 50_000_000
        ).encoded()
        bad.append(Data(repeating: 0, count: 40))
        parser.append(bad + Self.packet(sequence: 2, jpeg: Self.jpeg(size: 128, fill: 2)))
        #expect(parser.nextPacket()?.header.sequence == 2)
        #expect(parser.discardedBytes == bad.count)
    }

    @Test func skipsAPayloadThatIsNotAJPEG() {
        var parser = FrameStreamParser()
        var notJPEG = Self.packet(sequence: 1, jpeg: Self.jpeg(size: 128, fill: 1))
        notJPEG[FrameHeader.size] = 0x00
        parser.append(notJPEG + Self.packet(sequence: 2, jpeg: Self.jpeg(size: 128, fill: 2)))
        #expect(parser.nextPacket()?.header.sequence == 2)
    }

    @Test func waitsForTheRestOfAFrame() {
        var parser = FrameStreamParser()
        let packet = Self.packet(sequence: 4, jpeg: Self.jpeg(size: 1000, fill: 4))
        parser.append(packet.prefix(500))
        #expect(parser.nextPacket() == nil)
        parser.append(packet.dropFirst(500))
        #expect(parser.nextPacket()?.header.sequence == 4)
    }

    static func jpeg(size: Int, fill: UInt8) -> Data {
        var data = Data([0xFF, 0xD8])
        data.append(Data(repeating: fill, count: size - 4))
        data.append(contentsOf: [0xFF, 0xD9])
        return data
    }

    static func packet(sequence: UInt32, jpeg: Data) -> Data {
        FrameHeader(
            sequence: sequence,
            deviceMicroseconds: UInt64(sequence) * 100_000,
            width: 1024,
            height: 768,
            modeValue: 1,
            quality: 13,
            temperatureTenths: 512,
            payloadLength: UInt32(jpeg.count)
        ).encoded() + jpeg
    }
}
