import Foundation
import Network

public struct LocalAPIClient: Sendable {
    public let socketPath: String
    public let maximumResponseBytes: Int

    public init(socketPath: String = LocalAPIPaths.socketPath, maximumResponseBytes: Int = LineBuffer.maximumLineBytes) {
        self.socketPath = socketPath
        self.maximumResponseBytes = maximumResponseBytes
    }

    // Without the loopback limit, Network registers the Unix socket on every interface and logs errors.
    static var parameters: NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        return parameters
    }

    /// Throws `.appNotRunning` only when no request byte left this process, so a caller
    /// can launch the app and send again. Any later failure throws `.connectionLost`.
    public func send(_ request: LocalRequest) async throws(XiaoCamError) -> LocalResponse {
        let queue = DispatchQueue(label: "art.aayush.xiaocam.local-api.client")
        let connection = NWConnection(to: .unix(path: socketPath), using: Self.parameters)
        defer { connection.cancel() }
        do {
            try await connection.start(on: queue, timeout: .seconds(3))
        } catch {
            throw XiaoCamError(.appNotRunning, "app not running: nothing answers on \(socketPath).")
        }
        var data: Data
        do {
            data = try LocalAPICoding.encoder().encode(request)
        } catch {
            throw XiaoCamError(.badRequest, "The request could not be encoded: \(error.localizedDescription)")
        }
        data.append(0x0A)
        do {
            try await connection.sendData(data)
        } catch {
            throw Self.connectionLost
        }
        var lines = LineBuffer(limit: maximumResponseBytes)
        while true {
            let chunk: Data?
            do {
                chunk = try await connection.receiveChunk(maximumLength: 1 << 20, on: queue)
            } catch {
                throw Self.connectionLost
            }
            guard let chunk else { throw Self.connectionLost }
            lines.append(chunk)
            if let line = lines.nextLine() {
                do {
                    return try LocalAPICoding.decoder().decode(LocalResponse.self, from: line)
                } catch {
                    throw XiaoCamError(.failed, "XiaoCam sent an answer that is not valid: \(error.localizedDescription)")
                }
            }
            guard !lines.isOverflowing else {
                throw XiaoCamError(.failed, "XiaoCam sent an answer larger than \(maximumResponseBytes >> 20) MB.")
            }
        }
    }

    public func isReachable() async -> Bool {
        let queue = DispatchQueue(label: "art.aayush.xiaocam.local-api.probe")
        let connection = NWConnection(to: .unix(path: socketPath), using: Self.parameters)
        defer { connection.cancel() }
        do {
            try await connection.start(on: queue, timeout: .seconds(1))
            return true
        } catch {
            return false
        }
    }

    private static let connectionLost = XiaoCamError(
        .connectionLost,
        "XiaoCam closed the connection before it answered. The request may have run; check the camera state before you try again."
    )
}
