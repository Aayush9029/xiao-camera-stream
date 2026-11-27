/// Captures and permanent mode or settings writes share the camera. A temporary mode
/// (switch, capture, restore) needs it alone, so nothing runs in or overwrites that mode.
/// A waiting exclusive request blocks new shared requests, so it cannot starve.
public actor CameraAccess {
    private enum Waiter {
        case shared(CheckedContinuation<Void, Never>)
        case exclusive(CheckedContinuation<Void, Never>)

        var isExclusive: Bool {
            if case .exclusive = self { true } else { false }
        }
    }

    private var sharedHolders = 0
    private var isHeldExclusively = false
    private var waiters: [Waiter] = []

    public init() {}

    public func shared<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquireShared()
        defer { releaseShared() }
        return try await operation()
    }

    public func exclusive<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquireExclusive()
        defer { releaseExclusive() }
        return try await operation()
    }

    private func acquireShared() async {
        guard isHeldExclusively || waiters.contains(where: \.isExclusive) else {
            sharedHolders += 1
            return
        }
        await withCheckedContinuation { waiters.append(.shared($0)) }
    }

    private func acquireExclusive() async {
        guard isHeldExclusively || sharedHolders > 0 || !waiters.isEmpty else {
            isHeldExclusively = true
            return
        }
        await withCheckedContinuation { waiters.append(.exclusive($0)) }
    }

    private func releaseShared() {
        sharedHolders -= 1
        grantWaiters()
    }

    private func releaseExclusive() {
        isHeldExclusively = false
        grantWaiters()
    }

    private func grantWaiters() {
        while let next = waiters.first, !isHeldExclusively {
            switch next {
            case let .exclusive(continuation):
                guard sharedHolders == 0 else { return }
                waiters.removeFirst()
                isHeldExclusively = true
                continuation.resume()
            case let .shared(continuation):
                waiters.removeFirst()
                sharedHolders += 1
                continuation.resume()
            }
        }
    }
}
