import CasePaths
import Foundation
import Tagged

public struct CaptureJob: Codable, Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, String>

    @CasePathable
    public enum State: Codable, Equatable, Sendable {
        case running(progress: Double)
        case done(fetched: Bool)
        case failed(XiaoCamError)
    }

    public let id: ID
    public var kind: CaptureKind
    public var state: State
    public var createdAt: Date
    public var finishedAt: Date?

    public init(id: ID, kind: CaptureKind, state: State, createdAt: Date, finishedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.state = state
        self.createdAt = createdAt
        self.finishedAt = finishedAt
    }

    public var isFinished: Bool { !state.is(\.running) }
}
