import Foundation

public struct CaptureFrameInfo: Codable, Equatable, Sendable {
    public var index: Int
    public var capturedAt: Date
    public var offset: Double

    public init(index: Int, capturedAt: Date, offset: Double) {
        self.index = index
        self.capturedAt = capturedAt
        self.offset = offset
    }
}

public struct CaptureResult: Codable, Equatable, Sendable {
    public var kind: CaptureKind
    public var data: Data
    public var fileExtension: String
    public var width: Int
    public var height: Int
    public var mode: String?
    public var enhanced: Bool
    public var timestamped: Bool
    public var frames: [CaptureFrameInfo]
    public var interval: Double?
    public var duration: Double?
    public var fps: Double?
    public var columns: Int?
    public var rows: Int?

    public init(
        kind: CaptureKind,
        data: Data,
        fileExtension: String,
        width: Int,
        height: Int,
        mode: String?,
        enhanced: Bool,
        timestamped: Bool,
        frames: [CaptureFrameInfo],
        interval: Double? = nil,
        duration: Double? = nil,
        fps: Double? = nil,
        columns: Int? = nil,
        rows: Int? = nil
    ) {
        self.kind = kind
        self.data = data
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
        self.mode = mode
        self.enhanced = enhanced
        self.timestamped = timestamped
        self.frames = frames
        self.interval = interval
        self.duration = duration
        self.fps = fps
        self.columns = columns
        self.rows = rows
    }
}
