import Foundation
import Testing
@testable import XiaoCamCore

struct CameraHTTPTests {
    @Test func acceptsOnlyTheXiaoFirmware() throws {
        let firmware = #"{"device":"xiao-esp32s3-stream","fw":"4.1","mode":"balanced","width":1024}"#
        let status = try CameraHTTP.decodeStatus(Data(firmware.utf8), host: "192.168.2.106")
        #expect(status.isXiaoCamera)
        #expect(status.width == 1024)

        #expect(throws: CameraError.notACamera(host: "192.168.4.1")) {
            try CameraHTTP.decodeStatus(Data(#"{"error":"not found","code":404}"#.utf8), host: "192.168.4.1")
        }
        #expect(throws: CameraError.notACamera(host: "192.168.4.1")) {
            try CameraHTTP.decodeStatus(Data(#"{"device":"router","mode":"balanced"}"#.utf8), host: "192.168.4.1")
        }
        #expect(throws: CameraError.notACamera(host: "printer.local")) {
            try CameraHTTP.decodeStatus(Data("<html>login</html>".utf8), host: "printer.local")
        }
    }
}
