import SwiftUI

struct CameraConnectionSection: View {
    let model: CameraModel

    var body: some View {
        Section("Camera") {
            LabeledContent("Status") {
                ConnectionStatusLabel(state: model.connectionState)
            }
            HostField(host: model.savedHost ?? "") { host in
                Task { await model.connectButtonTapped(host: host) }
            }
            LabeledContent("Find Camera") {
                HStack {
                    if model.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Rescan") { Task { await model.rescanButtonTapped() } }
                        .disabled(model.isScanning)
                }
            }
            ForEach(model.cameras) { camera in
                LabeledContent(camera.host) {
                    Button("Connect") { Task { await model.connectButtonTapped(host: camera.host) } }
                        .disabled(model.connectionState == .live(host: camera.host))
                }
            }
            if let commandError = model.commandError {
                Label(commandError, systemImage: "exclamationmark.triangle.fill")
                    .settingFootnote()
                    .foregroundStyle(.orange)
            }
            Text("Away from your Wi‑Fi, join the XIAO-Cam network.")
                .settingFootnote()
        }
    }
}
