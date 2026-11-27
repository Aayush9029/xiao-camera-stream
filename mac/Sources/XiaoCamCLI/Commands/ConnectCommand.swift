import ArgumentParser
import XiaoCamKit

struct ConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Use the camera at a host name or an IP address, and remember it."
    )

    @Argument(help: "For example 192.168.2.106 or xiao-cam.local.")
    var host: String

    func run() async throws {
        try await Console.run {
            guard let device = try await AppConnection.send(.connect(host: host)).device else {
                throw XiaoCamError(.failed, "XiaoCam sent no status.")
            }
            Console.out("live \(host) \(StatusPrinter.device(device))")
        }
    }
}
