import Foundation
import Network
import OSLog

public actor LocalAPIServer {
    public typealias Handler = @Sendable (LocalRequest) async -> LocalResponse

    public static let maximumConnections = 16
    public static let maximumRequestBytes = 1 << 20
    public static let idleTimeout: Duration = .seconds(30)

    private static let logger = Logger(subsystem: "art.aayush.xiaocam", category: "LocalAPIServer")

    public nonisolated let socketPath: String
    private nonisolated let ownership = SocketOwnership()
    private let queue = DispatchQueue(label: "art.aayush.xiaocam.local-api")
    private let encoder = LocalAPICoding.encoder()
    private let decoder = LocalAPICoding.decoder()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: (connection: NWConnection, task: Task<Void, Never>)] = [:]

    public init(socketPath: String = LocalAPIPaths.socketPath) {
        self.socketPath = socketPath
    }

    public var activeConnectionCount: Int { connections.count }

    public func start(handler: @escaping Handler) async throws(XiaoCamError) {
        guard listener == nil else { return }
        do {
            try LocalAPIPaths.prepareDirectory(for: socketPath)
        } catch {
            throw XiaoCamError(.failed, "Could not make \(socketPath): \(error.localizedDescription)")
        }
        try await removeStaleSocket()

        let parameters = LocalAPIClient.parameters
        parameters.requiredLocalEndpoint = .unix(path: socketPath)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw XiaoCamError(.failed, "Could not listen on \(socketPath): \(error.localizedDescription)")
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection, handler: handler) }
        }
        do {
            try await listener.start(on: queue, timeout: .seconds(5))
        } catch {
            listener.cancel()
            throw XiaoCamError(.failed, "Could not listen on \(socketPath): \(error.localizedDescription)")
        }
        guard chmod(socketPath, 0o600) == 0, ownership.claim(socketPath) else {
            let reason = String(cString: strerror(errno))
            listener.cancel()
            unlink(socketPath)
            throw XiaoCamError(.failed, "Could not make \(socketPath) private: \(reason)")
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard case let .failed(error) = state else { return }
            Self.logger.error("Local API failed: \(error.localizedDescription, privacy: .public)")
            Task { await self?.stop() }
        }
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for (connection, task) in connections.values {
            task.cancel()
            connection.cancel()
        }
        connections.removeAll()
        ownership.release(socketPath)
    }

    public nonisolated func removeSocketIfOwned() {
        ownership.release(socketPath)
    }

    private func removeStaleSocket() async throws(XiaoCamError) {
        var info = stat()
        guard lstat(socketPath, &info) == 0 else {
            guard errno == ENOENT else {
                throw XiaoCamError(.failed, "Could not check \(socketPath): \(String(cString: strerror(errno)))")
            }
            return
        }
        guard info.st_mode & S_IFMT == S_IFSOCK else {
            throw XiaoCamError(.failed, "\(socketPath) exists and is not a socket. Move it away, then open XiaoCam again.")
        }
        guard info.st_uid == getuid() else {
            throw XiaoCamError(.failed, "\(socketPath) belongs to another user.")
        }
        if await LocalAPIClient(socketPath: socketPath).isReachable() {
            throw XiaoCamError(.busy, "Another XiaoCam app already answers on \(socketPath).")
        }
        guard unlink(socketPath) == 0 || errno == ENOENT else {
            throw XiaoCamError(.failed, "Could not remove the old socket \(socketPath): \(String(cString: strerror(errno)))")
        }
    }

    private func accept(_ connection: NWConnection, handler: @escaping Handler) {
        guard listener != nil, connections.count < Self.maximumConnections else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        let task = Task {
            await serve(connection, handler: handler)
            connections[id] = nil
        }
        connections[id] = (connection, task)
    }

    private func serve(_ connection: NWConnection, handler: Handler) async {
        defer { connection.cancel() }
        do {
            try await connection.start(on: queue, timeout: .seconds(5))
        } catch {
            return
        }
        var lines = LineBuffer(limit: Self.maximumRequestBytes)
        while !Task.isCancelled {
            let chunk: Data?
            do {
                chunk = try await connection.receiveChunk(maximumLength: 64 << 10, timeout: Self.idleTimeout, on: queue)
            } catch {
                return
            }
            guard let chunk else { return }
            lines.append(chunk)
            while let line = lines.nextLine() {
                let response: LocalResponse
                do {
                    response = await handler(try decoder.decode(LocalRequest.self, from: line))
                } catch {
                    response = LocalResponse(error: XiaoCamError(.badRequest, "The request is not valid: \(error.localizedDescription)"))
                }
                guard await send(response, on: connection) else { return }
            }
            if lines.isOverflowing {
                _ = await send(LocalResponse(error: XiaoCamError(.badRequest, "The request is larger than \(Self.maximumRequestBytes) bytes.")), on: connection)
                return
            }
        }
    }

    private func send(_ response: LocalResponse, on connection: NWConnection) async -> Bool {
        var data: Data
        do {
            data = try encoder.encode(response)
        } catch {
            data = (try? encoder.encode(LocalResponse(error: XiaoCamError(.failed, "The answer could not be encoded.")))) ?? Data()
        }
        data.append(0x0A)
        do {
            try await connection.sendData(data)
            return true
        } catch {
            return false
        }
    }
}
