import Foundation
import Network

public struct ConnectionTimeoutError: Error, Sendable {}

extension NWConnection {
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

    public func receiveChunk(
        maximumLength: Int,
        timeout: Duration? = nil,
        on queue: DispatchQueue
    ) async throws -> Data? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, any Error>) in
                let once = OnceFlag()
                receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                    guard once.claim() else { return }
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
                if let timeout {
                    queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
                        guard once.claim() else { return }
                        self?.cancel()
                        continuation.resume(throwing: ConnectionTimeoutError())
                    }
                }
            }
        } onCancel: {
            cancel()
        }
    }

    public func sendData(_ data: Data) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        } onCancel: {
            cancel()
        }
        try Task.checkCancellation()
    }
}

extension Duration {
    public var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
