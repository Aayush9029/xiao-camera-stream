import Foundation

public enum CameraSetting: String, CaseIterable, Codable, Identifiable, Sendable {
    case framesize
    case quality
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
    case udpMbps = "udp_mbps"

    public var id: Self { self }

    public var key: String { rawValue }

    public var range: ClosedRange<Int> {
        switch self {
        case .framesize: 0...19
        case .quality: 4...63
        case .brightness, .contrast, .sharpness: -3...3
        case .saturation: -4...4
        case .denoise: 0...8
        case .aeLevel: -5...5
        case .gainCeiling: 0...6
        case .aec2, .nightMode, .hmirror, .vflip: 0...1
        case .udpMbps: 4...32
        }
    }

    public var isToggle: Bool { range == 0...1 }

    public func validate(_ value: Int) throws(CameraSettingError) -> CameraSettingValue {
        guard range.contains(value) else {
            throw .outOfRange(setting: self, value: value)
        }
        return CameraSettingValue(setting: self, value: value)
    }

    public func parseValue(_ text: String) throws(CameraSettingError) -> CameraSettingValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if isToggle, let toggle = Self.toggleWords[trimmed] {
            return CameraSettingValue(setting: self, value: toggle)
        }
        guard let value = Int(trimmed) else {
            throw .notANumber(key: key, value: text)
        }
        return try validate(value)
    }

    public static func parse(assignment: String) throws(CameraSettingError) -> CameraSettingValue {
        let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else {
            throw .malformed(assignment)
        }
        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        guard let setting = CameraSetting(rawValue: key) else {
            throw .unknownKey(key)
        }
        return try setting.parseValue(String(parts[1]))
    }

    public static func parse(assignments: [String]) throws(CameraSettingError) -> [CameraSettingValue] {
        var values: [CameraSettingValue] = []
        for assignment in assignments {
            let value = try parse(assignment: assignment)
            guard !values.contains(where: { $0.setting == value.setting }) else {
                throw .duplicate(value.setting)
            }
            values.append(value)
        }
        guard !values.isEmpty else { throw .empty }
        return values
    }

    private static let toggleWords: [String: Int] = [
        "on": 1, "off": 0, "true": 1, "false": 0, "yes": 1, "no": 0,
    ]
}
