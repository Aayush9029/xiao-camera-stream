import SwiftUI

struct ToggleTile: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    var isEnabled = true
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Spacer(minLength: 4)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(isOn ? "On" : "Off")
                    .font(.system(size: 11))
                    .opacity(0.6)
            }
            .foregroundStyle(isOn ? .black : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .frame(height: 66)
            .background(
                isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial),
                in: .rect(cornerRadius: 14, style: .continuous)
            )
            .contentShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.18), value: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

#Preview {
    HStack {
        ToggleTile(title: "Night Mode", systemImage: "moon.fill", isOn: true) { _ in }
        ToggleTile(title: "Mirror", systemImage: "arrow.left.and.right", isOn: false) { _ in }
    }
    .frame(width: 236)
    .padding()
}
