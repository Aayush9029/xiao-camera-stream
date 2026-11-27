import AppKit
import SwiftUI
import XiaoCamKit

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: CameraModel, navigation: SettingsNavigation, tab: SettingsTab?) {
        if let tab {
            navigation.tab = tab
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let content = SettingsView(model: model, navigation: navigation)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "XiaoCam Settings"
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // Dropping the hosting view ends the panes' tasks, so a hidden Camera pane stops the stream.
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}
