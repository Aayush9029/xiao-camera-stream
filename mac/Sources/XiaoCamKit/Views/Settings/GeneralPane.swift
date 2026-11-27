import SwiftUI

struct GeneralPane: View {
    let model: CameraModel
    @State private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        SettingsForm {
            Section {
                HStack(alignment: .top, spacing: 20) {
                    ToggleCard(
                        title: "Open at Login",
                        description: "XiaoCam starts when you log in, so the camera and the xiaocam command are ready.",
                        icon: "power",
                        isOn: launchAtLogin.isEnabled,
                        action: { launchAtLogin.set(!launchAtLogin.isEnabled) }
                    ) {
                        SettingsIllustration(name: .launchAtLogin, isOn: launchAtLogin.isEnabled)
                    }

                    ToggleCard(
                        title: "Enhance Image",
                        description: "Removes noise, sharpens detail, and adds a little color to each capture. Each capture takes a little longer.",
                        icon: "wand.and.stars",
                        isOn: model.enhanceImage,
                        action: model.enhanceImageToggled
                    ) {
                        SettingsIllustration(name: .enhanceImage, isOn: model.enhanceImage)
                    }

                    ToggleCard(
                        title: "Timestamp on Captures",
                        description: "Puts the date and time on each photo, grid cell, and video frame.",
                        icon: "clock",
                        isOn: model.timestampOverlay,
                        action: model.timestampOverlayToggled
                    ) {
                        SettingsIllustration(name: .timestamp, isOn: model.timestampOverlay)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))

                if let failureMessage = launchAtLogin.failureMessage {
                    Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                        .settingFootnote()
                        .foregroundStyle(.orange)
                }
            }

            CameraConnectionSection(model: model)
        }
        .task { launchAtLogin.refresh() }
    }
}
