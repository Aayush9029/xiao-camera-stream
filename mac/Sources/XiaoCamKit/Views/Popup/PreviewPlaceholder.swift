import SwiftUI

struct PreviewPlaceholder: View {
    let state: ConnectionState
    var isWaitingForFrame = false

    var body: some View {
        VStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 22, weight: .light))
            }
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.5))
    }

    private var isBusy: Bool {
        switch state {
        case .searching, .connecting: true
        case .live: isWaitingForFrame
        case .offline: false
        }
    }

    private var title: String {
        switch state {
        case .searching: "Searching"
        case .connecting: "Connecting"
        case .live: "Starting"
        case .offline: "Offline"
        }
    }
}

#Preview {
    VStack {
        PreviewPlaceholder(state: .searching)
        PreviewPlaceholder(state: .live(host: "192.168.2.106"), isWaitingForFrame: true)
        PreviewPlaceholder(state: .offline(reason: "No camera found"))
    }
    .frame(width: 304, height: 700)
}
