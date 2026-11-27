import SwiftUI

public struct CameraPopupView: View {
    let model: CameraModel
    let showsControls: Bool
    let onSettings: () -> Void
    let onQuit: () -> Void

    @State private var isHovering = false

    private let radius: CGFloat = 22

    public init(
        model: CameraModel,
        showsControls: Bool = false,
        onSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.model = model
        self.showsControls = showsControls
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        CameraStage(model: model, showsControls: showsControls || isHovering)
            .frame(width: 340)
            .overlay(alignment: .topLeading) {
                if let captureStatus {
                    Text(captureStatus)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .glassEffect(.regular, in: .capsule)
                        .environment(\.colorScheme, .dark)
                        .padding(10)
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            }
            .contentShape(.rect(cornerRadius: radius, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.18), value: captureStatus)
            .contextMenu {
                Button("Capture Photo", systemImage: "camera") {
                    Task { await model.capturePhotoButtonTapped() }
                }
                .disabled(!model.connectionState.is(\.live) || model.photoCapture.is(\.capturing))
                Button("Settings…", systemImage: "gearshape", action: onSettings)
                Divider()
                Button("Quit XiaoCam", systemImage: "power", action: onQuit)
            }
            .background {
                Group {
                    Button("Settings", action: onSettings)
                        .keyboardShortcut(",", modifiers: .command)
                    Button("Quit", action: onQuit)
                        .keyboardShortcut("q", modifiers: .command)
                }
                .opacity(0)
                .accessibilityHidden(true)
            }
    }

    private var captureStatus: String? {
        switch model.photoCapture {
        case .idle, .capturing: nil
        case .saved: "Saved"
        case .failed: "Failed"
        }
    }
}

#Preview {
    CameraPopupView(model: CameraModel(), showsControls: true)
        .padding()
}
