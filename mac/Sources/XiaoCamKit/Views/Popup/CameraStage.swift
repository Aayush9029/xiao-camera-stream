import SwiftUI

struct CameraStage: View {
    let model: CameraModel
    var showsControls = true

    var body: some View {
        content
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if controlsVisible, let status = model.status {
                    PreviewBadge(width: status.width, height: status.height, fps: model.receiveFPS)
                        .padding(10)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if controlsVisible {
                    ModeControl(mode: model.status?.cameraMode) { mode in
                        await model.modeSelected(mode)
                    }
                    .frame(maxWidth: 280)
                    .padding(10)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .environment(\.colorScheme, .dark)
            .animation(.easeOut(duration: 0.18), value: controlsVisible)
            .animation(.smooth(duration: 0.3), value: aspectRatio)
    }

    private var isLive: Bool { model.connectionState.is(\.live) }

    private var controlsVisible: Bool { showsControls && isLive }

    private var aspectRatio: CGFloat {
        guard let status = model.status, status.width > 0, status.height > 0 else { return 4 / 3 }
        return CGFloat(status.width) / CGFloat(status.height)
    }

    @ViewBuilder
    private var content: some View {
        if isLive, model.hasPreview {
            LivePreview(model: model)
        } else {
            PreviewPlaceholder(state: model.connectionState, isWaitingForFrame: true)
        }
    }
}
