import Dependencies
import Foundation

public actor CaptureJobs {
    public static let retainedJobs = 8
    public static let maximumRunning = 4

    private struct Entry {
        var job: CaptureJob
        var task: Task<CaptureResult, any Error>?
        var result: CaptureResult?
    }

    private let runner: CaptureRunner
    private var entries: [CaptureJob.ID: Entry] = [:]
    private var order: [CaptureJob.ID] = []
    private var completionOrder: [CaptureJob.ID] = []
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    public init(source: CaptureSource, access: CameraAccess = CameraAccess()) {
        runner = CaptureRunner(source: source, access: access)
    }

    public func start(_ request: CaptureRequest) throws(XiaoCamError) -> CaptureJob {
        let running = entries.values.count { !$0.job.isFinished }
        guard running < Self.maximumRunning else {
            throw XiaoCamError(.busy, "\(Self.maximumRunning) captures already run. Wait for one to finish.")
        }
        let id = makeID()
        let job = CaptureJob(id: id, kind: request.kind, state: .running(progress: 0), createdAt: now)
        let runner = runner
        let task = Task<CaptureResult, any Error> {
            do {
                let result = try await runner.run(request) { progress in
                    await self.update(id, progress: progress)
                }
                complete(id, with: .success(result))
                return result
            } catch {
                complete(id, with: .failure(error))
                throw error
            }
        }
        entries[id] = Entry(job: job, task: task)
        order.append(id)
        return job
    }

    public func run(_ request: CaptureRequest) async throws(XiaoCamError) -> CaptureResult {
        let job = try start(request)
        return try await wait(for: job.id).result
    }

    public func wait(for id: CaptureJob.ID) async throws(XiaoCamError) -> (job: CaptureJob, result: CaptureResult) {
        guard let entry = entries[id] else { throw Self.notFound(id) }
        guard let task = entry.task else { return try take(id) }
        switch await task.result {
        case let .success(result):
            var job = entries[id]?.job ?? entry.job
            job.state = .done(fetched: true)
            if entries[id] != nil {
                entries[id]?.job.state = .done(fetched: true)
                entries[id]?.result = nil
            }
            return (job, result)
        case let .failure(error):
            throw XiaoCamError(error)
        }
    }

    public func take(_ id: CaptureJob.ID) throws(XiaoCamError) -> (job: CaptureJob, result: CaptureResult) {
        guard var entry = entries[id] else { throw Self.notFound(id) }
        switch entry.job.state {
        case .running:
            throw XiaoCamError(.busy, "Job \(id) still runs.")
        case let .failed(error):
            throw error
        case .done:
            guard let result = entry.result else {
                throw XiaoCamError(.notFound, "The result of job \(id) was already fetched.")
            }
            entry.result = nil
            entry.job.state = .done(fetched: true)
            entries[id] = entry
            return (entry.job, result)
        }
    }

    public func job(_ id: CaptureJob.ID) -> CaptureJob? {
        entries[id]?.job
    }

    public func list() -> [CaptureJob] {
        order.compactMap { entries[$0]?.job }
    }

    public func cancelAll() {
        for entry in entries.values { entry.task?.cancel() }
    }

    private func update(_ id: CaptureJob.ID, progress: Double) {
        guard entries[id]?.job.state.is(\.running) == true else { return }
        entries[id]?.job.state = .running(progress: progress)
    }

    private func complete(_ id: CaptureJob.ID, with outcome: Result<CaptureResult, any Error>) {
        guard var entry = entries[id] else { return }
        entry.job.finishedAt = now
        switch outcome {
        case let .success(result):
            entry.result = result
            entry.job.state = .done(fetched: false)
        case let .failure(error):
            entry.job.state = .failed(XiaoCamError(error))
        }
        entry.task = nil
        entries[id] = entry
        completionOrder.append(id)
        prune()
    }

    private func prune() {
        while completionOrder.count > Self.retainedJobs {
            let id = completionOrder.removeFirst()
            entries[id] = nil
            order.removeAll { $0 == id }
        }
    }

    private func makeID() -> CaptureJob.ID {
        while true {
            let text = uuid().uuidString
            let id = CaptureJob.ID(rawValue: String(text[text.index(text.endIndex, offsetBy: -6)...]).lowercased())
            if entries[id] == nil { return id }
        }
    }

    private static func notFound(_ id: CaptureJob.ID) -> XiaoCamError {
        XiaoCamError(.notFound, "No job \(id). Run xiaocam jobs to see the known jobs.")
    }
}
