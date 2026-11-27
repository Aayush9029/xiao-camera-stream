import Synchronization

final class WakeSignal: Sendable {
    private struct State {
        var isPending = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func signal() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard let waiter = state.waiter else {
                state.isPending = true
                return nil
            }
            state.waiter = nil
            return waiter
        }
        waiter?.resume()
    }

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumesNow = state.withLock { state -> Bool in
                    if state.isPending {
                        state.isPending = false
                        return true
                    }
                    guard !Task.isCancelled else { return true }
                    state.waiter = continuation
                    return false
                }
                if resumesNow { continuation.resume() }
            }
        } onCancel: {
            let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }
    }
}
