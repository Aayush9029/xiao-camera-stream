import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false
    private(set) var failureMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failureMessage = nil
        } catch {
            failureMessage = error.localizedDescription
        }
        refresh()
    }
}
