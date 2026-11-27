import Observation

@MainActor
@Observable
public final class SettingsNavigation {
    public var tab: SettingsTab? = .general

    public init() {}
}
