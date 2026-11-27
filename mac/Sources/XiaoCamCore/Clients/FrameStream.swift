import Foundation
import Network

enum FrameStream {
    static let port: UInt16 = 82

    static func frames(host: String) -> AsyncThrowingStream<Frame, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(4)) { continuation in
            let task = Task {
                do {
                    try await run(host: host, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        host: String,
        continuation: AsyncThrowingStream<Frame, any Error>.Continuation
    ) async throws {
        let queue = DispatchQueue(label: "art.aayush.xiaocam.stream")
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        defer { connection.cancel() }

        do {
            try await connection.start(on: queue, timeout: .seconds(4))
        } catch is ConnectionTimeoutError {
            throw CameraError.timedOut(host: host)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CameraError.unreachable(host: host, reason: error.localizedDescription)
        }

        var parser = FrameStreamParser()
        while true {
            try Task.checkCancellation()
            let chunk: Data?
            do {
                chunk = try await connection.receiveChunk(maximumLength: 256 << 10, timeout: .seconds(5), on: queue)
            } catch is ConnectionTimeoutError {
                throw CameraError.streamStalled
            }
            guard let chunk else { throw CameraError.streamClosed }
            parser.append(chunk)
            while let packet = parser.nextPacket() {
                continuation.yield(Frame(header: packet.header, jpeg: packet.jpeg, receivedAt: Date()))
            }
        }
    }
}
