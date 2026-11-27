import SwiftUI

struct CameraControlsColumn: View {
    let model: CameraModel

    private let adjustments: [CameraSetting] = [.brightness, .contrast, .saturation, .sharpness, .denoise, .aeLevel]
    private let switches: [CameraSetting] = [.nightMode, .hmirror, .vflip]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(switches) { setting in
                    ToggleTile(
                        title: setting.title,
                        systemImage: setting.symbol,
                        isOn: model.status?.value(for: setting) == 1,
                        isEnabled: isLive
                    ) { isOn in
                        Task { await model.settingChanged(setting, to: isOn ? 1 : 0) }
                    }
                }
            }
            ForEach(adjustments) { setting in
                SliderTile(
                    title: setting.title,
                    range: setting.range,
                    value: model.status?.value(for: setting) ?? 0,
                    isEnabled: isLive
                ) { value in
                    Task { await model.settingChanged(setting, to: value) }
                }
            }
        }
    }

    private var isLive: Bool { model.connectionState.is(\.live) }
}
