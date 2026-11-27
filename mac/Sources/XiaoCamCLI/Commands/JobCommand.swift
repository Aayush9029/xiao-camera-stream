import ArgumentParser
import XiaoCamKit

struct JobCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "job",
        abstract: "Show a capture job. When it is done, save its result and print the path."
    )

    @Argument(help: "The job id that grid --detach printed.")
    var id: String

    @Flag(name: .long, help: "Wait until the job is done.")
    var wait = false

    @OptionGroup var output: CaptureOutputOptions

    func run() async throws {
        try await Console.run {
            let response = try await AppConnection.send(.job(id: id, wait: wait))
            guard let job = response.job else { throw XiaoCamError(.failed, "XiaoCam sent no job.") }
            if let result = response.result {
                try output.emit(job: job, result: result)
                return
            }
            if job.state == .done(fetched: true) {
                throw XiaoCamError(.notFound, "the result of job \(id) was already fetched.")
            }
            if output.json {
                try Console.json(JobSummary(job))
            } else {
                Console.out(JobSummary(job).line)
            }
        }
    }
}
