import SwiftUI

struct LivePreview: View {
    let model: CameraModel

    var body: some View {
        PreviewLayerView(image: model.preview)
    }
}
