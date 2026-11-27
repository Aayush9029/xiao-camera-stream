import Foundation

public enum CameraSettingError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case malformed(String)
    case unknownKey(String)
    case notANumber(key: String, value: String)
    case outOfRange(setting: CameraSetting, value: Int)
    case duplicate(CameraSetting)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Give at least one setting, for example brightness=1."
        case let .malformed(text):
            "\"\(text)\" is not key=value."
        case let .unknownKey(key):
            "Unknown setting \"\(key)\". Known settings: \(CameraSetting.allCases.map(\.key).joined(separator: ", "))."
        case let .notANumber(key, value):
            "\(key) needs a whole number, not \"\(value)\"."
        case let .outOfRange(setting, value):
            "\(setting.key)=\(value) is out of range \(setting.range.lowerBound)...\(setting.range.upperBound)."
        case let .duplicate(setting):
            "\(setting.key) is given more than one time."
        }
    }
}
