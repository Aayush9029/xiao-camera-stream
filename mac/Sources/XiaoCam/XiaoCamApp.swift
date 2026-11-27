import SwiftUI

@main
struct XiaoCamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.settingsMenuItemSelected() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
