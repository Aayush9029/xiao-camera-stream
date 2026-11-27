import AppKit
import SwiftUI

struct PreviewLayerView: NSViewRepresentable {
    let image: CGImage?

    func makeNSView(context: Context) -> PreviewLayerNSView {
        PreviewLayerNSView()
    }

    func updateNSView(_ view: PreviewLayerNSView, context: Context) {
        view.image = image
    }
}
