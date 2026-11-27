import ArgumentParser
import XiaoCamKit

struct DiscoverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discover",
        abstract: "Find cameras with Bonjour, xiao-cam.local, the saved host, and 192.168.4.1."
    )

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func run() async throws {
        try await Console.run {
            let cameras = try await AppConnection.send(.discover).cameras ?? []
            if json {
                try Console.json(cameras)
            } else {
                for camera in cameras {
                    Console.out("\(camera.host)  \(camera.source.rawValue)  \(StatusPrinter.device(camera.status))  \(camera.status.rssi) dBm")
                }
            }
            guard !cameras.isEmpty else { throw XiaoCamError.cameraOffline("no camera found on this network.") }
        }
    }
}
