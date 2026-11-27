import ArgumentParser
import XiaoCamKit

struct GridCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "grid",
        abstract: "Take a photo at an interval and put all photos in one grid image.",
        discussion: "Blocks until the grid is done, then prints its path. With --detach, prints a job id at once."
    )

    @Option(name: .long, help: "Seconds between photos (0.5 or more).")
    var every: Double = 5

    @Option(name: .customLong("for"), help: "Total seconds (up to 3600). At most 36 photos; a longer run spreads them out.")
    var duration: Double = 30

    @Option(name: .long, help: "Columns in the grid. Default: about square.")
    var columns: Int?

    @Flag(name: .long, help: "Print the job id at once. Get the grid later with xiaocam job <id> --wait.")
    var detach = false

    @OptionGroup var image: ImageOptions
    @OptionGroup var output: CaptureOutputOptions

    func validate() throws {
        guard every > 0, duration >= 0 else { throw ValidationError("--every must be above 0 and --for 0 or more.") }
        if let columns, columns < 1 { throw ValidationError("--columns must be 1 or more.") }
    }

    func run() async throws {
        try await Console.run {
            let options = GridOptions(every: every, duration: duration, columns: columns, enhance: image.enhance, timestamp: image.timestamp)
            let response = try await AppConnection.send(.capture(.grid(options), detach: detach))
            guard let job = response.job else { throw XiaoCamError(.failed, "XiaoCam sent no job.") }
            if detach {
                if output.json {
                    try Console.json(JobSummary(job))
                } else {
                    Console.out(job.id.rawValue)
                }
                return
            }
            guard let result = response.result else { throw XiaoCamError(.failed, "XiaoCam sent no grid.") }
            try output.emit(job: job, result: result)
        }
    }
}
