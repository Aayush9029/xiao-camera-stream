import Synchronization

public final class OnceFlag: Sendable {
    private let state = Mutex(false)

    public init() {}

    public func claim() -> Bool {
        state.withLock { claimed in
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
