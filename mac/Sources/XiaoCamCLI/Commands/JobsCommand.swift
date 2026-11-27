import ArgumentParser
import XiaoCamKit

struct JobsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jobs",
        abstract: "List capture jobs that run or that keep a result."
    )

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func run() async throws {
        try await Console.run {
            let jobs = (try await AppConnection.send(.jobs).jobs ?? []).map(JobSummary.init)
            if json {
                try Console.json(jobs)
            } else if jobs.isEmpty {
                Console.out("no jobs")
            } else {
                jobs.forEach { Console.out($0.line) }
            }
        }
    }
}
