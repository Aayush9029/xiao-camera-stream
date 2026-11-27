import ArgumentParser
import XiaoCamKit

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Print the mode and each sensor setting with its range."
    )

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func run() async throws {
        try await Console.run {
            guard let device = try await AppConnection.send(.config).device else {
                throw XiaoCamError(.failed, "XiaoCam sent no status.")
            }
            if json {
                let settings = Dictionary(uniqueKeysWithValues: CameraSetting.allCases.map { ($0.key, device.value(for: $0)) })
                try Console.json(ConfigSummary(mode: device.mode, width: device.width, height: device.height, settings: settings))
                return
            }
            Console.out("mode=\(device.mode)  (\(device.width)x\(device.height))")
            for setting in CameraSetting.allCases {
                let range = "\(setting.range.lowerBound)...\(setting.range.upperBound)"
                Console.out("\(setting.key)=\(device.value(for: setting))  (\(range))")
            }
        }
    }
}
