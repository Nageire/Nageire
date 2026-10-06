import SwiftUI

/// Shown above the stream only while GitHub refuses to take what the app sends. A failure that passes on its own shows nothing.
struct RefusedBanner: View {
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't write to the repository.")
                    .font(.subheadline.weight(.semibold))
                Text("Check it in Settings.")
                    .font(.footnote)
            }
            .foregroundStyle(.accentText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.accentWash, in: .rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RefusedBanner {}
        .padding(Spacing.gutter)
        .background(.paper)
}
