import Foundation
import Network

extension NWListener {
    public func start(on queue: DispatchQueue, timeout: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let once = OnceFlag()
                stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if once.claim() { continuation.resume() }
                    case let .waiting(error), let .failed(error):
                        if once.claim() { continuation.resume(throwing: error) }
                    case .cancelled:
                        if once.claim() { continuation.resume(throwing: CancellationError()) }
                    default:
                        break
                    }
                }
                start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
                    guard once.claim() else { return }
                    self?.cancel()
                    continuation.resume(throwing: ConnectionTimeoutError())
                }
            }
        } onCancel: {
            cancel()
        }
    }
}
