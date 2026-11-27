import SwiftUI

struct PreviewBadge: View {
    let width: Int
    let height: Int
    let fps: Double

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        let size = "\(width) × \(height)"
        guard fps >= 0.5 else { return size }
        return "\(size)  \(fps.formatted(.number.precision(.fractionLength(0)))) fps"
    }
}

#Preview {
    VStack {
        PreviewBadge(width: 1024, height: 768, fps: 14.2)
        PreviewBadge(width: 2048, height: 1536, fps: 0)
    }
    .padding()
    .background(.gray)
}
