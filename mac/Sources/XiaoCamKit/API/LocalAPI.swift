import Foundation

public enum LocalRequest: Codable, Equatable, Sendable {
    case status
    case discover
    case connect(host: String)
    case mode(CameraMode)
    case set([CameraSettingValue])
    case config
    case capture(CaptureRequest, detach: Bool)
    case job(id: String, wait: Bool)
    case jobs
}

public struct LocalResponse: Codable, Equatable, Sendable {
    public var error: XiaoCamError?
    public var status: AppStatus?
    public var device: DeviceStatus?
    public var cameras: [DiscoveredCamera]?
    public var job: CaptureJob?
    public var jobs: [CaptureJob]?
    public var result: CaptureResult?

    public init(
        error: XiaoCamError? = nil,
        status: AppStatus? = nil,
        device: DeviceStatus? = nil,
        cameras: [DiscoveredCamera]? = nil,
        job: CaptureJob? = nil,
        jobs: [CaptureJob]? = nil,
        result: CaptureResult? = nil
    ) {
        self.error = error
        self.status = status
        self.device = device
        self.cameras = cameras
        self.job = job
        self.jobs = jobs
        self.result = result
    }
}

public enum LocalAPICoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
