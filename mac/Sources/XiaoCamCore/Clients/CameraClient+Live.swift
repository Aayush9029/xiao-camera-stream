import Dependencies
import Foundation

extension CameraClient: DependencyKey {
    public static var liveValue: CameraClient {
        let control = CameraHTTP(timeout: 4)
        let stills = CameraHTTP(timeout: 8)
        return CameraClient(
            status: { try await control.status(host: $0) },
            setMode: { try await stills.setMode(host: $0, mode: $1) },
            updateSettings: { try await stills.updateSettings(host: $0, values: $1) },
            capture: { try await stills.capture(host: $0) },
            frames: { FrameStream.frames(host: $0) }
        )
    }
}
