import ArgumentParser
import XiaoCamKit

struct ModeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mode",
        abstract: "Set the camera mode. This also resets the image settings to the mode defaults.",
        discussion: "performance: 480x320, most frames, for motion. balanced: 1024x768. quality: 2048x1536, for text and small detail."
    )

    @Argument(help: "performance, balanced, or quality.")
    var mode: CameraMode

    func run() async throws {
        try await Console.run {
            guard let device = try await AppConnection.send(.mode(mode)).device else {
                throw XiaoCamError(.failed, "XiaoCam sent no status.")
            }
            Console.out(StatusPrinter.device(device))
        }
    }
}
