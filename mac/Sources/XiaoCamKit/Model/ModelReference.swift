@MainActor
final class ModelReference {
    weak var model: CameraModel?
}

extension CaptureSource {
    @MainActor
    static func model(_ reference: ModelReference) -> CaptureSource {
        CaptureSource(
            liveHost: { @MainActor in
                guard let model = reference.model else { throw XiaoCamError.cameraOffline("XiaoCam is quitting") }
                return try await model.waitForLiveHost()
            },
            frames: { @MainActor in
                reference.model?.frameSubscription() ?? AsyncStream { $0.finish() }
            },
            defaults: { @MainActor in
                CaptureDefaults(
                    enhance: reference.model?.enhanceImage ?? false,
                    timestamp: reference.model?.timestampOverlay ?? true
                )
            },
            status: { @MainActor in reference.model?.status },
            statusChanged: { @MainActor status in reference.model?.deviceStatusChanged(status) }
        )
    }
}
