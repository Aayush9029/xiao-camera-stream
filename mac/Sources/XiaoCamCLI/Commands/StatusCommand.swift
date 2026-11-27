import ArgumentParser
import XiaoCamKit

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the camera state, mode, frame rate, and signal. Exits 2 when the camera is not live."
    )

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func run() async throws {
        try await Console.run {
            let response = try await AppConnection.send(.status)
            guard let status = response.status else { throw XiaoCamError(.failed, "XiaoCam sent no status.") }
            if json {
                try Console.json(status)
            } else {
                StatusPrinter.print(status)
            }
            guard status.connection.is(\.live) else { throw ExitCode(2) }
        }
    }
}
