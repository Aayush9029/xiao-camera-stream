import Foundation
import Testing
import XiaoCamCore

struct LineBufferTests {
    @Test func splitsLinesAcrossChunks() {
        var buffer = LineBuffer()
        buffer.append(Data(#"{"a":1}"#.utf8) + Data([0x0A]) + Data(#"{"b""#.utf8))
        #expect(buffer.nextLine() == Data(#"{"a":1}"#.utf8))
        #expect(buffer.nextLine() == nil)
        buffer.append(Data(#":2}"#.utf8) + Data([0x0A]))
        #expect(buffer.nextLine() == Data(#"{"b":2}"#.utf8))
        #expect(buffer.nextLine() == nil)
    }
}
