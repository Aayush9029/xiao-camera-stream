import Foundation
import XiaoCamKit

struct CaptureSummary: Encodable {
    var path: String
    var job: String
    var kind: CaptureKind
    var width: Int
    var height: Int
    var mode: String?
    var enhanced: Bool
    var timestamped: Bool
    var frames: [CaptureFrameInfo]
    var interval: Double?
    var duration: Double?
    var fps: Double?
    var columns: Int?
    var rows: Int?

    init(path: URL, job: CaptureJob, result: CaptureResult) {
        self.path = path.path(percentEncoded: false)
        self.job = job.id.rawValue
        kind = result.kind
        width = result.width
        height = result.height
        mode = result.mode
        enhanced = result.enhanced
        timestamped = result.timestamped
        frames = result.frames
        interval = result.interval
        duration = result.duration
        fps = result.fps
        columns = result.columns
        rows = result.rows
    }
}
