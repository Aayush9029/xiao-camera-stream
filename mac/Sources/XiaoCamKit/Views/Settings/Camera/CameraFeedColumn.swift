import SwiftUI

struct CameraFeedColumn: View {
    let model: CameraModel
    let height: CGFloat
    let maxWidth: CGFloat

    @State private var footerHeight: CGFloat = 0

    private let spacing: CGFloat = 10

    var body: some View {
        VStack(spacing: spacing) {
            CameraStage(model: model, showsControls: false)
                .frame(width: width, height: stageHeight)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            VStack(spacing: spacing) {
                ModeControl(mode: model.status?.cameraMode, isEnabled: isLive) { mode in
                    await model.modeSelected(mode)
                }

                HStack(spacing: 8) {
                    StatTile(label: "Resolution", value: resolution)
                    StatTile(label: "Frame Rate", value: frameRate)
                    StatTile(label: "Signal", value: signal)
                    StatTile(label: "Heat", value: temperature)
                }

                if let commandError = model.commandError {
                    Label(commandError, systemImage: "exclamationmark.triangle.fill")
                        .settingFootnote()
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: width)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { footerHeight = $0 }
        }
        .animation(.smooth(duration: 0.3), value: width)
    }

    private var aspectRatio: CGFloat {
        guard let status = model.status, status.width > 0, status.height > 0 else { return 4 / 3 }
        return CGFloat(status.width) / CGFloat(status.height)
    }

    private var width: CGFloat {
        let fitted = max(height - footerHeight - spacing, 0) * aspectRatio
        return max(min(fitted, maxWidth), 1)
    }

    private var stageHeight: CGFloat { width / aspectRatio }

    private var isLive: Bool { model.connectionState.is(\.live) }

    private var resolution: String {
        guard let status = model.status, status.width > 0 else { return "—" }
        return "\(status.width)×\(status.height)"
    }

    private var frameRate: String {
        guard let status = model.status else { return "—" }
        let fps = model.receiveFPS >= 0.5 ? model.receiveFPS : status.captureFPS
        return "\(fps.formatted(.number.precision(.fractionLength(0)))) fps"
    }

    private var signal: String {
        guard let status = model.status else { return "—" }
        return status.wifiMode == "AP" ? "Direct" : "\(status.rssi) dBm"
    }

    private var temperature: String {
        guard let status = model.status else { return "—" }
        return "\(status.temperatureC.formatted(.number.precision(.fractionLength(0)))) °C"
    }
}
