extension CameraSetting {
    var title: String {
        switch self {
        case .framesize: "Frame Size"
        case .quality: "JPEG Quality"
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .saturation: "Saturation"
        case .sharpness: "Sharpness"
        case .denoise: "Noise Reduction"
        case .aeLevel: "Exposure"
        case .aec2: "Exposure Control"
        case .gainCeiling: "Gain Limit"
        case .nightMode: "Night"
        case .hmirror: "Mirror"
        case .vflip: "Flip"
        case .udpMbps: "UDP Rate"
        }
    }
}

extension CameraSetting {
    var symbol: String {
        switch self {
        case .nightMode: "moon.fill"
        case .hmirror: "arrow.left.and.right"
        case .vflip: "arrow.up.and.down"
        default: "slider.horizontal.3"
        }
    }
}
