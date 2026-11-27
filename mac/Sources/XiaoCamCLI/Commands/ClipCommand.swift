import ArgumentParser
import XiaoCamKit

struct ClipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clip",
        abstract: "Record a short H.264 video and print its path."
    )

    @Option(name: .customLong("for"), help: "Seconds to record (1 to 60).")
    var duration: Double = 10

    @Option(name: .long, help: "Most frames per second to keep (1 to 30). The camera mode sets the real rate.")
    var fps: Double = 10

    @OptionGroup var image: ImageOptions
    @OptionGroup var output: CaptureOutputOptions

    func run() async throws {
        try await Console.run {
            let options = ClipOptions(duration: duration, fps: fps, enhance: image.enhance, timestamp: image.timestamp)
            let response = try await AppConnection.send(.capture(.clip(options), detach: false))
            guard let job = response.job, let result = response.result else {
                throw XiaoCamError(.failed, "XiaoCam sent no video.")
            }
            try output.emit(job: job, result: result)
        }
    }
}
