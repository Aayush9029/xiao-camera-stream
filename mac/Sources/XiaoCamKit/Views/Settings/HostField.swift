import SwiftUI

struct HostField: View {
    @State private var host: String
    let onConnect: (String) -> Void

    init(host: String, onConnect: @escaping (String) -> Void) {
        _host = State(initialValue: host)
        self.onConnect = onConnect
    }

    var body: some View {
        LabeledContent("Address") {
            HStack {
                TextField("Address", text: $host, prompt: Text("xiao-cam.local"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onSubmit(connect)
                Button("Connect", action: connect)
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func connect() {
        onConnect(host)
    }
}

#Preview {
    Form {
        HostField(host: "192.168.2.106") { print($0) }
    }
    .formStyle(.grouped)
}
