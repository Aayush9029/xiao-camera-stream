import ArgumentParser
import XiaoCamKit

struct SetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Change sensor settings, for example: xiaocam set brightness=1 contrast=0",
        discussion: "Run xiaocam config to see each setting with its range. Toggles also take on and off."
    )

    @Argument(help: "One or more key=value pairs.")
    var assignments: [String]

    func run() async throws {
        try await Console.run {
            let values = try CameraSetting.parse(assignments: assignments)
            guard let device = try await AppConnection.send(.set(values)).device else {
                throw XiaoCamError(.failed, "XiaoCam sent no status.")
            }
            for value in values {
                Console.out("\(value.setting.key)=\(device.value(for: value.setting))")
            }
        }
    }
}
