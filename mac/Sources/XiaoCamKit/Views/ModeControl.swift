import SwiftUI

struct ModeControl: View {
    let mode: CameraMode?
    var isEnabled = true
    let onSelect: (CameraMode) async -> Void

    @Namespace private var thumb
    @State private var pending: CameraMode?
    @State private var width: CGFloat = 0

    private let modes = CameraMode.allCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(modes) { candidate in
                Text(candidate.rawValue.capitalized)
                    .font(.system(size: 11.5, weight: candidate == shown ? .semibold : .medium))
                    .foregroundStyle(candidate == shown ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if candidate == shown {
                            Capsule()
                                .fill(.primary.opacity(0.18))
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { pending = candidate(at: $0.location.x) }
                .onEnded { commit(candidate(at: $0.location.x)) }
        )
        .animation(.snappy(duration: 0.22), value: shown)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityRepresentation {
            Picker("Mode", selection: Binding(get: { shown }, set: { commit($0) })) {
                ForEach(modes) { Text($0.rawValue.capitalized).tag(Optional($0)) }
            }
        }
    }

    private var shown: CameraMode? { pending ?? mode }

    private func candidate(at x: CGFloat) -> CameraMode? {
        guard width > 0 else { return mode }
        let index = Int(x / (width / CGFloat(modes.count)))
        return modes[min(max(index, 0), modes.count - 1)]
    }

    private func commit(_ candidate: CameraMode?) {
        guard let candidate, candidate != mode else {
            pending = nil
            return
        }
        Task {
            pending = candidate
            await onSelect(candidate)
            pending = nil
        }
    }
}

#Preview {
    VStack {
        ModeControl(mode: .balanced) { _ in }
        ModeControl(mode: nil, isEnabled: false) { _ in }
    }
    .frame(width: 280)
    .padding()
}
