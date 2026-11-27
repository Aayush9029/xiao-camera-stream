import ArgumentParser
import XiaoCamKit

struct CaptureOutputOptions: ParsableArguments {
    @Option(name: .long, help: "A file or a folder for the result. Default: ~/Library/Caches/XiaoCam/captures (newest 24 captures kept).")
    var out: String?

    @Flag(name: .long, help: "Print JSON metadata (path, frame times, size, mode) instead of the bare path.")
    var json = false

    func emit(job: CaptureJob, result: CaptureResult) throws {
        let url = try CaptureFileStore().write(result, to: out, jobID: job.id.rawValue)
        if json {
            try Console.json(CaptureSummary(path: url, job: job, result: result))
        } else {
            Console.out(url.path(percentEncoded: false))
        }
    }
}
