import Foundation
import Testing
import XiaoCamCore

struct DeviceStatusTests {
    @Test func decodesTheFirmwareStatus() throws {
        let json = #"""
        {"device":"xiao-esp32s3-stream","fw":"4.1","sensor":"OV3660","xclk_mhz":20,"mode":"balanced","framesize":12,"width":1024,"height":768,"quality":13,"capture_fps":6.00,"stream_fps":0.00,"tx_kbps":0.0,"mean_frame_bytes":21734,"frames_captured":727,"frames_sent":0,"frames_dropped":0,"cam_errors":0,"nack_retrans":0,"udp_mbps":14,"tx_power_dbm":13.00,"clients_udp":0,"clients_bin":0,"clients_mjpeg":0,"temp_c":55.9,"rssi":-53,"wifi_mode":"STA","ssid":"Home","ip":"192.168.2.106","free_heap":4164392,"free_psram":3966916,"uptime_s":137,"brightness":0,"contrast":0,"saturation":0,"sharpness":0,"denoise":2,"ae_level":1,"aec2":1,"gainceiling":2,"night_mode":0,"hmirror":0,"vflip":1}
        """#
        let status = try JSONDecoder().decode(DeviceStatus.self, from: Data(json.utf8))
        #expect(status.cameraMode == .balanced)
        #expect(status.firmware == "4.1")
        #expect(status.width == 1024)
        #expect(status.captureFPS == 6)
        #expect(status.temperatureC == 55.9)
        #expect(status.rssi == -53)
        #expect(status.ip == "192.168.2.106")
        #expect(status.value(for: .denoise) == 2)
        #expect(status.value(for: .aeLevel) == 1)
        #expect(status.value(for: .vflip) == 1)
    }

    @Test func toleratesMissingAndMistypedKeys() throws {
        let json = #"{"mode":"custom","width":"wide","rssi":-70}"#
        let status = try JSONDecoder().decode(DeviceStatus.self, from: Data(json.utf8))
        #expect(status.cameraMode == nil)
        #expect(status.width == 0)
        #expect(status.rssi == -70)
        #expect(status.firmware == "")
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(DeviceStatus.preview)
        #expect(try JSONDecoder().decode(DeviceStatus.self, from: data) == .preview)
    }
}
