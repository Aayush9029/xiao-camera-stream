import AppKit
import XiaoCamKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: XiaoCamAppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.anotherInstanceIsRunning else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        let model = XiaoCamAppModel()
        self.model = model
        model.start()

        let environment = ProcessInfo.processInfo.environment
        if environment["XIAOCAM_SHOW_POPUP"] != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                model.statusItemClicked()
            }
        }
        if let tab = environment["XIAOCAM_SHOW_SETTINGS"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                model.showSettings(tab: SettingsTab(rawValue: tab))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func settingsMenuItemSelected() {
        model?.showSettings(tab: nil)
    }

    private static var anotherInstanceIsRunning: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != current && !$0.isTerminated }
    }
}
