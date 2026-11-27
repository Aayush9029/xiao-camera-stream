import AppKit
import OSLog
import XiaoCamKit

@MainActor
final class XiaoCamAppModel {
    private static let logger = Logger(subsystem: "art.aayush.xiaocam", category: "App")

    let camera = CameraModel()

    private let navigation = SettingsNavigation()
    private let settingsWindow = SettingsWindowController()
    private let server = LocalAPIServer()
    private var statusItem: StatusItemController?
    private var popup: PopupPanelController?
    private var cameraTask: Task<Void, Never>?

    func start() {
        statusItem = StatusItemController(model: camera) { [weak self] in
            self?.statusItemClicked()
        }
        popup = PopupPanelController(
            content: CameraPopupView(
                model: camera,
                showsControls: ProcessInfo.processInfo.environment["XIAOCAM_SHOW_CONTROLS"] != nil,
                onSettings: { [weak self] in self?.settingsButtonTapped() },
                onQuit: { [weak self] in self?.quitButtonTapped() }
            )
        ) { [weak self] in
            self?.popupDismissed()
        }
        cameraTask = Task { [camera] in await camera.task() }
        startServer()
    }

    func stop() {
        cameraTask?.cancel()
        server.removeSocketIfOwned()
    }

    func statusItemClicked() {
        guard let popup else { return }
        if popup.isVisible || popup.wasJustDismissed {
            popup.dismiss()
            return
        }
        guard let anchor = statusItem?.buttonFrame else { return }
        popup.show(below: anchor)
        statusItem?.setHighlighted(true)
        camera.addStreamDemand()
    }

    func showSettings(tab: SettingsTab?) {
        settingsWindow.show(model: camera, navigation: navigation, tab: tab)
    }

    private func popupDismissed() {
        statusItem?.setHighlighted(false)
        camera.removeStreamDemand()
    }

    private func settingsButtonTapped() {
        popup?.dismiss()
        showSettings(tab: nil)
    }

    private func quitButtonTapped() {
        popup?.dismiss()
        NSApp.terminate(nil)
    }

    private func startServer() {
        let handler = LocalAPIHandler(model: camera)
        let server = server
        Task {
            do {
                try await server.start { request in await handler.handle(request) }
            } catch {
                let error = XiaoCamError(error)
                Self.logger.error("Local API did not start: \(error.message, privacy: .public)")
                if error.code == .busy { NSApp.terminate(nil) }
            }
        }
    }
}
