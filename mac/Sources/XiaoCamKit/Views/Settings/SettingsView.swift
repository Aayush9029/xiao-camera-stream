import SwiftUI

public struct SettingsView: View {
    let model: CameraModel
    @Bindable var navigation: SettingsNavigation

    public init(model: CameraModel, navigation: SettingsNavigation) {
        self.model = model
        self.navigation = navigation
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: $navigation.tab) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    SettingsTabIcon(tab: tab, isSelected: tab == currentTab)
                }
                .padding(.vertical, 4)
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            pane
                .navigationTitle("")
                .background {
                    VisualEffectBackground(material: .underWindowBackground)
                        .ignoresSafeArea()
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 440)
    }

    private var currentTab: SettingsTab { navigation.tab ?? .general }

    @ViewBuilder
    private var pane: some View {
        switch currentTab {
        case .general: GeneralPane(model: model)
        case .camera: CameraPane(model: model)
        case .agents: AgentsPane()
        }
    }
}

#Preview {
    SettingsView(model: CameraModel(), navigation: SettingsNavigation())
}
