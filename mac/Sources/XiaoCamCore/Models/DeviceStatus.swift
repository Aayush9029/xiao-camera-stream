public struct DeviceStatus: Codable, Equatable, Sendable {
    public static let firmwareDevice = "xiao-esp32s3-stream"

    public var device = ""
    public var firmware = ""
    public var sensor = ""
    public var mode = ""
    public var framesize = 0
    public var width = 0
    public var height = 0
    public var quality = 0
    public var captureFPS = 0.0
    public var streamFPS = 0.0
    public var txKbps = 0.0
    public var meanFrameBytes = 0
    public var framesCaptured = 0
    public var framesSent = 0
    public var framesDropped = 0
    public var cameraErrors = 0
    public var udpMbps = 0
    public var txPowerDbm = 0.0
    public var udpClients = 0
    public var binaryClients = 0
    public var mjpegClients = 0
    public var temperatureC = 0.0
    public var rssi = 0
    public var wifiMode = ""
    public var ssid = ""
    public var ip = ""
    public var freeHeap = 0
    public var freePSRAM = 0
    public var uptimeSeconds = 0
    public var brightness = 0
    public var contrast = 0
    public var saturation = 0
    public var sharpness = 0
    public var denoise = 0
    public var aeLevel = 0
    public var aec2 = 0
    public var gainCeiling = 0
    public var nightMode = 0
    public var hmirror = 0
    public var vflip = 0

    public init() {}

    public var cameraMode: CameraMode? { CameraMode(rawValue: mode) }

    public var isXiaoCamera: Bool { device == Self.firmwareDevice }

    public func value(for setting: CameraSetting) -> Int {
        switch setting {
        case .framesize: framesize
        case .quality: quality
        case .brightness: brightness
        case .contrast: contrast
        case .saturation: saturation
        case .sharpness: sharpness
        case .denoise: denoise
        case .aeLevel: aeLevel
        case .aec2: aec2
        case .gainCeiling: gainCeiling
        case .nightMode: nightMode
        case .hmirror: hmirror
        case .vflip: vflip
        case .udpMbps: udpMbps
        }
    }

    public mutating func apply(_ value: CameraSettingValue) {
        switch value.setting {
        case .framesize: framesize = value.value
        case .quality: quality = value.value
        case .brightness: brightness = value.value
        case .contrast: contrast = value.value
        case .saturation: saturation = value.value
        case .sharpness: sharpness = value.value
        case .denoise: denoise = value.value
        case .aeLevel: aeLevel = value.value
        case .aec2: aec2 = value.value
        case .gainCeiling: gainCeiling = value.value
        case .nightMode: nightMode = value.value
        case .hmirror: hmirror = value.value
        case .vflip: vflip = value.value
        case .udpMbps: udpMbps = value.value
        }
    }

    enum CodingKeys: String, CodingKey {
        case device
        case firmware = "fw"
        case sensor
        case mode
        case framesize
        case width
        case height
        case quality
        case captureFPS = "capture_fps"
        case streamFPS = "stream_fps"
        case txKbps = "tx_kbps"
        case meanFrameBytes = "mean_frame_bytes"
        case framesCaptured = "frames_captured"
        case framesSent = "frames_sent"
        case framesDropped = "frames_dropped"
        case cameraErrors = "cam_errors"
        case udpMbps = "udp_mbps"
        case txPowerDbm = "tx_power_dbm"
        case udpClients = "clients_udp"
        case binaryClients = "clients_bin"
        case mjpegClients = "clients_mjpeg"
        case temperatureC = "temp_c"
        case rssi
        case wifiMode = "wifi_mode"
        case ssid
        case ip
        case freeHeap = "free_heap"
        case freePSRAM = "free_psram"
        case uptimeSeconds = "uptime_s"
        case brightness
        case contrast
        case saturation
        case sharpness
        case denoise
        case aeLevel = "ae_level"
        case aec2
        case gainCeiling = "gainceiling"
        case nightMode = "night_mode"
        case hmirror
        case vflip
    }
}

extension DeviceStatus {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.init()
        device = field(.device, device)
        firmware = field(.firmware, firmware)
        sensor = field(.sensor, sensor)
        mode = field(.mode, mode)
        framesize = field(.framesize, framesize)
        width = field(.width, width)
        height = field(.height, height)
        quality = field(.quality, quality)
        captureFPS = field(.captureFPS, captureFPS)
        streamFPS = field(.streamFPS, streamFPS)
        txKbps = field(.txKbps, txKbps)
        meanFrameBytes = field(.meanFrameBytes, meanFrameBytes)
        framesCaptured = field(.framesCaptured, framesCaptured)
        framesSent = field(.framesSent, framesSent)
        framesDropped = field(.framesDropped, framesDropped)
        cameraErrors = field(.cameraErrors, cameraErrors)
        udpMbps = field(.udpMbps, udpMbps)
        txPowerDbm = field(.txPowerDbm, txPowerDbm)
        udpClients = field(.udpClients, udpClients)
        binaryClients = field(.binaryClients, binaryClients)
        mjpegClients = field(.mjpegClients, mjpegClients)
        temperatureC = field(.temperatureC, temperatureC)
        rssi = field(.rssi, rssi)
        wifiMode = field(.wifiMode, wifiMode)
        ssid = field(.ssid, ssid)
        ip = field(.ip, ip)
        freeHeap = field(.freeHeap, freeHeap)
        freePSRAM = field(.freePSRAM, freePSRAM)
        uptimeSeconds = field(.uptimeSeconds, uptimeSeconds)
        brightness = field(.brightness, brightness)
        contrast = field(.contrast, contrast)
        saturation = field(.saturation, saturation)
        sharpness = field(.sharpness, sharpness)
        denoise = field(.denoise, denoise)
        aeLevel = field(.aeLevel, aeLevel)
        aec2 = field(.aec2, aec2)
        gainCeiling = field(.gainCeiling, gainCeiling)
        nightMode = field(.nightMode, nightMode)
        hmirror = field(.hmirror, hmirror)
        vflip = field(.vflip, vflip)
    }
}
