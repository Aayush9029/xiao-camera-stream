import Foundation
import Network
import Testing
@testable import XiaoCamKit

struct LocalAPITests {
    static func temporarySocketPath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "xc-\(UUID().uuidString.prefix(8)).sock")
            .path(percentEncoded: false)
    }

    @Test func theClientStopsReadingAnAnswerOverItsLimit() async throws {
        let path = Self.temporarySocketPath()
        let server = LocalAPIServer(socketPath: path)
        try await server.start { _ in
            LocalResponse(result: CaptureResult(
                kind: .clip, data: Data(count: 3 << 20), fileExtension: "mp4", width: 1, height: 1,
                mode: nil, enhanced: false, timestamped: false, frames: []
            ))
        }
        await #expect(throws: XiaoCamError(.failed, "XiaoCam sent an answer larger than 1 MB.")) {
            try await LocalAPIClient(socketPath: path, maximumResponseBytes: 1 << 20).send(.jobs)
        }
        let full = try await LocalAPIClient(socketPath: path).send(.jobs)
        #expect(full.result?.data.count == 3 << 20)
        await server.stop()
    }

    @Test func aConnectionThatClosesAfterTheRequestIsNotReportedAsAppNotRunning() async throws {
        let path = Self.temporarySocketPath()
        let parameters = LocalAPIClient.parameters
        parameters.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "test.listener")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, _, _ in connection.cancel() }
        }
        try await listener.start(on: queue, timeout: .seconds(2))
        defer {
            listener.cancel()
            unlink(path)
        }

        await #expect {
            try await LocalAPIClient(socketPath: path).send(.mode(.quality))
        } throws: { error in
            (error as? XiaoCamError)?.code == .connectionLost
        }
    }

    @Test func refusesToReplaceAFileThatIsNotASocket() async throws {
        let path = Self.temporarySocketPath()
        try Data("keep me".utf8).write(to: URL(filePath: path))
        defer { unlink(path) }

        await #expect(throws: XiaoCamError(.failed, "\(path) exists and is not a socket. Move it away, then open XiaoCam again.")) {
            try await LocalAPIServer(socketPath: path).start { _ in LocalResponse() }
        }
        #expect(try Data(contentsOf: URL(filePath: path)) == Data("keep me".utf8))
    }

    @Test func aServerThatLostTheRaceLeavesTheOtherSocketInPlace() async throws {
        let path = Self.temporarySocketPath()
        let first = LocalAPIServer(socketPath: path)
        try await first.start { _ in LocalResponse(jobs: []) }
        let second = LocalAPIServer(socketPath: path)
        await #expect(throws: XiaoCamError(.busy, "Another XiaoCam app already answers on \(path).")) {
            try await second.start { _ in LocalResponse() }
        }

        second.removeSocketIfOwned()
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try await LocalAPIClient(socketPath: path).send(.jobs).jobs == [])

        first.removeSocketIfOwned()
        #expect(!FileManager.default.fileExists(atPath: path))
        await first.stop()
    }

    @Test func carriesRequestsAndLargeResultsOverTheSocket() async throws {
        let path = Self.temporarySocketPath()
        let payload = Data((0..<(3 << 20)).map { UInt8($0 % 251) })
        let server = LocalAPIServer(socketPath: path)
        try await server.start { request in
            switch request {
            case .status:
                LocalResponse(status: AppStatus(
                    connection: .live(host: "10.0.0.5"), device: .preview, receiveFPS: 12,
                    isStreaming: true, savedHost: "10.0.0.5", enhanceImage: false, timestampOverlay: true
                ))
            case let .capture(.grid(options), detach):
                LocalResponse(result: CaptureResult(
                    kind: .grid, data: payload, fileExtension: "jpg", width: 2000, height: 1000,
                    mode: "balanced", enhanced: false, timestamped: !detach, frames: [],
                    interval: options.every, duration: options.duration
                ))
            default:
                LocalResponse(error: XiaoCamError(.badRequest, "unsupported"))
            }
        }

        let client = LocalAPIClient(socketPath: path)
        let status = try await client.send(.status).status
        #expect(status?.connection == .live(host: "10.0.0.5"))
        #expect(status?.device == .preview)

        let result = try await client.send(.capture(.grid(GridOptions(every: 2, duration: 8)), detach: false)).result
        #expect(result?.data == payload)
        #expect(result?.interval == 2)

        let rejected = try await client.send(.jobs)
        #expect(rejected.error == XiaoCamError(.badRequest, "unsupported"))

        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)

        await #expect(throws: XiaoCamError.self) {
            try await LocalAPIServer(socketPath: path).start { _ in LocalResponse() }
        }

        await server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        await #expect(throws: XiaoCamError(.appNotRunning, "app not running: nothing answers on \(path).")) {
            try await client.send(.status)
        }
    }
}
