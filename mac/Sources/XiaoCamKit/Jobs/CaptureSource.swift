public struct CaptureDefaults: Equatable, Sendable {
    public var enhance: Bool
    public var timestamp: Bool

    public init(enhance: Bool, timestamp: Bool) {
        self.enhance = enhance
        self.timestamp = timestamp
    }
}

public struct CaptureSource: Sendable {
    public var liveHost: @Sendable () async throws -> String
    public var frames: @Sendable () async -> AsyncStream<Frame>
    public var defaults: @Sendable () async -> CaptureDefaults
    public var status: @Sendable () async -> DeviceStatus?
    public var statusChanged: @Sendable (DeviceStatus) async -> Void

    public init(
        liveHost: @escaping @Sendable () async throws -> String,
        frames: @escaping @Sendable () async -> AsyncStream<Frame>,
        defaults: @escaping @Sendable () async -> CaptureDefaults,
        status: @escaping @Sendable () async -> DeviceStatus?,
        statusChanged: @escaping @Sendable (DeviceStatus) async -> Void
    ) {
        self.liveHost = liveHost
        self.frames = frames
        self.defaults = defaults
        self.status = status
        self.statusChanged = statusChanged
    }
}
