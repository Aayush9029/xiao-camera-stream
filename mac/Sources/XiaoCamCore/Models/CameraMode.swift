public enum CameraMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case performance
    case balanced
    case quality

    public var id: Self { self }

    public init?(headerValue: UInt8) {
        switch headerValue {
        case 0: self = .performance
        case 1: self = .balanced
        case 2: self = .quality
        default: return nil
        }
    }
}
