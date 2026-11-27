public struct AppStatus: Codable, Equatable, Sendable {
    public var connection: ConnectionState
    public var device: DeviceStatus?
    public var receiveFPS: Double
    public var isStreaming: Bool
    public var savedHost: String?
    public var enhanceImage: Bool
    public var timestampOverlay: Bool

    public init(
        connection: ConnectionState,
        device: DeviceStatus?,
        receiveFPS: Double,
        isStreaming: Bool,
        savedHost: String?,
        enhanceImage: Bool,
        timestampOverlay: Bool
    ) {
        self.connection = connection
        self.device = device
        self.receiveFPS = receiveFPS
        self.isStreaming = isStreaming
        self.savedHost = savedHost
        self.enhanceImage = enhanceImage
        self.timestampOverlay = timestampOverlay
    }
}
