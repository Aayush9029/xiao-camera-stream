import Foundation
import XiaoCamKit

struct JobSummary: Encodable {
    var id: String
    var kind: CaptureKind
    var state: String
    var progress: Double?
    var error: String?
    var createdAt: Date
    var finishedAt: Date?

    init(_ job: CaptureJob) {
        id = job.id.rawValue
        kind = job.kind
        createdAt = job.createdAt
        finishedAt = job.finishedAt
        switch job.state {
        case let .running(progress):
            state = "running"
            self.progress = progress
        case let .done(fetched):
            state = fetched ? "fetched" : "done"
        case let .failed(error):
            state = "failed"
            self.error = error.message
        }
    }

    var line: String {
        var text = "\(id)  \(kind.rawValue)  \(state)"
        if let progress { text += " \(Int((progress * 100).rounded()))%" }
        if let error { text += ": \(error)" }
        return text
    }
}
