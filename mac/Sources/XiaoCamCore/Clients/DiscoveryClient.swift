import Dependencies
import DependenciesMacros

public struct DiscoveredCamera: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case saved
        case bonjour
        case hostname
        case accessPoint
    }

    public var host: String
    public var source: Source
    public var status: DeviceStatus

    public init(host: String, source: Source, status: DeviceStatus) {
        self.host = host
        self.source = source
        self.status = status
    }

    public var id: String { host }
}

@DependencyClient
public struct DiscoveryClient: Sendable {
    public var discover: @Sendable (_ savedHost: String?) async -> [DiscoveredCamera] = { _ in [] }
}

extension DiscoveryClient: TestDependencyKey {
    public static var testValue: DiscoveryClient { DiscoveryClient() }
    public static var previewValue: DiscoveryClient {
        DiscoveryClient { _ in [DiscoveredCamera(host: "192.168.2.106", source: .bonjour, status: .preview)] }
    }
}

extension DependencyValues {
    public var discoveryClient: DiscoveryClient {
        get { self[DiscoveryClient.self] }
        set { self[DiscoveryClient.self] = newValue }
    }
}
