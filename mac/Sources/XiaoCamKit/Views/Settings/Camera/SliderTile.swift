import SwiftUI

struct SliderTile: View {
    let title: String
    let range: ClosedRange<Int>
    let value: Int
    var isEnabled = true
    let onCommit: (Int) -> Void

    @State private var draft: Double

    init(title: String, range: ClosedRange<Int>, value: Int, isEnabled: Bool = true, onCommit: @escaping (Int) -> Void) {
        self.title = title
        self.range = range
        self.value = value
        self.isEnabled = isEnabled
        self.onCommit = onCommit
        _draft = State(initialValue: Double(value))
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(Int(draft), format: .number.sign(strategy: .always(includingZero: false)))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $draft, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { isEditing in
                guard !isEditing, Int(draft) != value else { return }
                onCommit(Int(draft))
            }
            .controlSize(.small)
            .accessibilityLabel(title)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onChange(of: value) { draft = Double(value) }
    }
}

#Preview {
    VStack {
        SliderTile(title: "Brightness", range: -3...3, value: 1) { _ in }
        SliderTile(title: "Noise Reduction", range: 0...8, value: 2, isEnabled: false) { _ in }
    }
    .frame(width: 236)
    .padding()
}
