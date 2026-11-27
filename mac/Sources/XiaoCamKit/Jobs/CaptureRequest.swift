public enum CaptureKind: String, Codable, Sendable {
    case snap
    case grid
    case clip
}

public struct SnapOptions: Codable, Equatable, Sendable {
    public var enhance: Bool?
    public var timestamp: Bool?
    public var mode: CameraMode?

    public init(enhance: Bool? = nil, timestamp: Bool? = nil, mode: CameraMode? = nil) {
        self.enhance = enhance
        self.timestamp = timestamp
        self.mode = mode
    }
}

public struct GridOptions: Codable, Equatable, Sendable {
    public var every: Double
    public var duration: Double
    public var columns: Int?
    public var enhance: Bool?
    public var timestamp: Bool?

    public init(every: Double, duration: Double, columns: Int? = nil, enhance: Bool? = nil, timestamp: Bool? = nil) {
        self.every = every
        self.duration = duration
        self.columns = columns
        self.enhance = enhance
        self.timestamp = timestamp
    }
}

public struct ClipOptions: Codable, Equatable, Sendable {
    public var duration: Double
    public var fps: Double
    public var enhance: Bool?
    public var timestamp: Bool?

    public init(duration: Double, fps: Double = 10, enhance: Bool? = nil, timestamp: Bool? = nil) {
        self.duration = duration
        self.fps = fps
        self.enhance = enhance
        self.timestamp = timestamp
    }
}

public enum CaptureRequest: Codable, Equatable, Sendable {
    case snap(SnapOptions)
    case grid(GridOptions)
    case clip(ClipOptions)

    public var kind: CaptureKind {
        switch self {
        case .snap: .snap
        case .grid: .grid
        case .clip: .clip
        }
    }
}
