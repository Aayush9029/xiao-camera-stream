import SwiftUI

struct ConnectionStatusLabel: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
    }

    private var color: Color {
        switch state {
        case .live: .green
        case .searching, .connecting: .orange
        case .offline: .red
        }
    }

    private var title: String {
        switch state {
        case .searching: "Searching"
        case .connecting: "Connecting"
        case .live: "Live"
        case let .offline(reason): "Offline · \(reason)"
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        ConnectionStatusLabel(state: .searching)
        ConnectionStatusLabel(state: .live(host: "192.168.2.106"))
        ConnectionStatusLabel(state: .offline(reason: "No camera found on this network."))
    }
    .padding()
}
