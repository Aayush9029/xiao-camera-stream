import SwiftUI

public struct StatusItemView: View {
    let model: CameraModel

    public init(model: CameraModel) {
        self.model = model
    }

    public var body: some View {
        Image(systemName: "camera.aperture")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(model.connectionState.is(\.live) ? .primary : .tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch model.connectionState {
        case .searching: "XiaoCam, searching"
        case .connecting: "XiaoCam, connecting"
        case .live: "XiaoCam, live"
        case .offline: "XiaoCam, offline"
        }
    }
}
