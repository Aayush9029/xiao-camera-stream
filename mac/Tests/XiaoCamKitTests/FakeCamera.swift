import ConcurrencyExtras
import Foundation
import XiaoCamKit

final class FakeCamera: Sendable {
    struct State: Equatable {
        var status: DeviceStatus
        var modeCalls: [CameraMode] = []
        var settingsCalls: [[CameraSettingValue]] = []
        var capturedModes: [String] = []
    }

    let state: LockIsolated<State>
    let jpeg: Data

    init(status: DeviceStatus, jpeg: Data) {
        state = LockIsolated(State(status: status))
        self.jpeg = jpeg
    }

    var client: CameraClient {
        CameraClient(
            status: { _ in
                await Self.pause()
                return self.state.value.status
            },
            setMode: { _, mode in
                await Self.pause()
                return self.state.withValue { state in
                    state.modeCalls.append(mode)
                    state.status = Self.preset(mode, from: state.status)
                    return state.status
                }
            },
            updateSettings: { _, values in
                await Self.pause()
                return self.state.withValue { state in
                    state.settingsCalls.append(values)
                    values.forEach { state.status.apply($0) }
                    if values.contains(where: { $0.setting == .framesize }) { state.status.mode = "custom" }
                    return state.status
                }
            },
            capture: { _ in
                await Self.pause()
                self.state.withValue { $0.capturedModes.append($0.status.mode) }
                await Self.pause()
                return self.jpeg
            },
            frames: { _ in .finished() }
        )
    }

    static func preset(_ mode: CameraMode, from status: DeviceStatus) -> DeviceStatus {
        var status = status
        status.mode = mode.rawValue
        status.framesize = switch mode {
        case .performance: 9
        case .balanced: 12
        case .quality: 19
        }
        status.brightness = 0
        status.contrast = 0
        status.sharpness = mode == .quality ? 1 : 0
        return status
    }

    private static func pause() async {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
