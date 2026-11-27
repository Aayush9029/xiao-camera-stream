import SwiftUI

struct IllustrationBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.24, green: 0.27, blue: 0.52), Color(red: 0.16, green: 0.46, blue: 0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
