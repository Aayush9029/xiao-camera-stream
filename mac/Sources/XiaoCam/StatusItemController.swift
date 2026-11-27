import AppKit
import SwiftUI
import XiaoCamKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let hostingView: PassthroughHostingView<StatusItemView>
    private let onClick: () -> Void

    init(model: CameraModel, onClick: @escaping () -> Void) {
        self.onClick = onClick
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        hostingView = PassthroughHostingView(rootView: StatusItemView(model: model))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])

            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }
    }

    var buttonFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func setHighlighted(_ isHighlighted: Bool) {
        statusItem.button?.highlight(isHighlighted)
    }

    @objc private func statusItemClicked() {
        onClick()
    }
}
