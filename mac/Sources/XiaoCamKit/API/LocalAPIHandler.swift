@MainActor
public final class LocalAPIHandler {
    private let model: CameraModel

    public init(model: CameraModel) {
        self.model = model
    }

    public func handle(_ request: LocalRequest) async -> LocalResponse {
        do {
            return try await respond(to: request)
        } catch {
            return LocalResponse(error: error)
        }
    }

    private func respond(to request: LocalRequest) async throws(XiaoCamError) -> LocalResponse {
        switch request {
        case .status:
            await model.waitUntilSettled()
            return LocalResponse(status: model.appStatus)

        case .discover:
            return LocalResponse(cameras: await model.discover())

        case let .connect(host):
            return LocalResponse(device: try await model.connect(to: host))

        case let .mode(mode):
            return LocalResponse(device: try await model.setMode(mode))

        case let .set(values):
            let validated: [CameraSettingValue]
            do {
                validated = try values.map { try $0.setting.validate($0.value) }
            } catch {
                throw XiaoCamError(error)
            }
            return LocalResponse(device: try await model.updateSettings(validated))

        case .config:
            return LocalResponse(device: try await model.refreshStatus())

        case let .capture(request, detach):
            let job = try await model.jobs.start(request)
            if detach { return LocalResponse(job: job) }
            let finished = try await model.jobs.wait(for: job.id)
            return LocalResponse(job: finished.job, result: finished.result)

        case let .job(rawID, wait):
            let id = CaptureJob.ID(rawValue: rawID)
            if wait {
                let finished = try await model.jobs.wait(for: id)
                return LocalResponse(job: finished.job, result: finished.result)
            }
            guard let job = await model.jobs.job(id) else {
                throw XiaoCamError(.notFound, "No job \(rawID). Run xiaocam jobs to see the known jobs.")
            }
            if case let .failed(error) = job.state { throw error }
            guard job.state == .done(fetched: false) else { return LocalResponse(job: job) }
            let finished = try await model.jobs.take(id)
            return LocalResponse(job: finished.job, result: finished.result)

        case .jobs:
            return LocalResponse(jobs: await model.jobs.list())
        }
    }
}
