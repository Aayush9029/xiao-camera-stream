import Foundation

extension CameraClient {
    public static var preview: CameraClient {
        CameraClient(
            status: { _ in .preview },
            setMode: { _, mode in
                var status = DeviceStatus.preview
                status.mode = mode.rawValue
                return status
            },
            updateSettings: { _, values in
                var status = DeviceStatus.preview
                values.forEach { status.apply($0) }
                return status
            },
            capture: { _ in Data() },
            frames: { _ in .finished() }
        )
    }
}

extension DeviceStatus {
    public static var preview: DeviceStatus {
        var status = DeviceStatus()
        status.device = "xiao-esp32s3-stream"
        status.firmware = "4.1"
        status.sensor = "OV3660"
        status.mode = CameraMode.balanced.rawValue
        status.framesize = 12
        status.width = 1024
        status.height = 768
        status.quality = 13
        status.captureFPS = 6
        status.temperatureC = 52.4
        status.rssi = -53
        status.wifiMode = "STA"
        status.ip = "192.168.2.106"
        status.denoise = 2
        status.aeLevel = 1
        status.aec2 = 1
        status.gainCeiling = 2
        status.vflip = 1
        return status
    }
}
