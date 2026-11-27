import CasePaths

@CasePathable
public enum ConnectionState: Codable, Equatable, Sendable {
    case searching
    case connecting(host: String)
    case live(host: String)
    case offline(reason: String)

    public var host: String? {
        switch self {
        case let .connecting(host), let .live(host): host
        case .searching, .offline: nil
        }
    }
}
