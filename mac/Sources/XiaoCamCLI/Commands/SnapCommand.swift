import ArgumentParser
import XiaoCamKit

struct SnapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snap",
        abstract: "Take one photo and print its path."
    )

    @Option(name: .long, help: "Use this mode for the photo only, then go back. performance, balanced, or quality.")
    var mode: CameraMode?

    @OptionGroup var image: ImageOptions
    @OptionGroup var output: CaptureOutputOptions

    func run() async throws {
        try await Console.run {
            let options = SnapOptions(enhance: image.enhance, timestamp: image.timestamp, mode: mode)
            let response = try await AppConnection.send(.capture(.snap(options), detach: false))
            guard let job = response.job, let result = response.result else {
                throw XiaoCamError(.failed, "XiaoCam sent no photo.")
            }
            try output.emit(job: job, result: result)
        }
    }
}
