import SwiftUI

/// A hollow circle and the word: the note is not on GitHub yet. A sent note carries nothing.
struct UnsentMark: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .strokeBorder(.ink2, lineWidth: 1.5)
                .frame(width: 9, height: 9)
            Text("Unsent")
        }
        .font(.footnote)
        .foregroundStyle(.ink2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    UnsentMark()
        .padding()
        .background(.paper)
}
