import SwiftUI

struct CameraPane: View {
    let model: CameraModel

    @State private var controlsHeight: CGFloat = 0
    @State private var paneWidth: CGFloat = 0

    private let controlsWidth: CGFloat = 236
    private let spacing: CGFloat = 16
    private let margin: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            CameraFeedColumn(model: model, height: controlsHeight, maxWidth: feedMaxWidth)
            CameraControlsColumn(model: model)
                .frame(width: controlsWidth)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 }
        }
        .padding(.horizontal, margin)
        .padding(.bottom, margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { paneWidth = $0 }
        .task { await model.streamWhileVisible() }
    }

    private var feedMaxWidth: CGFloat {
        max(paneWidth - margin * 2 - spacing - controlsWidth, 0)
    }
}
