import AppKit
import SwiftUI

struct SettingsIllustration: View {
    enum Name: String {
        case launchAtLogin = "launch-at-login"
        case enhanceImage = "enhance-image"
        case timestamp
    }

    let name: Name
    let isOn: Bool

    var body: some View {
        Group {
            if let image = Self.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                IllustrationBackdrop()
            }
        }
        .saturation(isOn ? 1 : 0.35)
    }

    private static func image(named name: Name) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name.rawValue, withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
