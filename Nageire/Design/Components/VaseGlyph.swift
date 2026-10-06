import SwiftUI

/// The vase of the logo, as the glyph of the toss. It takes the color of the text beside it and its size.
struct VaseGlyph: View {
    var isCompact = false

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var compactHeight: CGFloat = 16

    var body: some View {
        Image(.vase)
            .resizable()
            .scaledToFit()
            .frame(height: isCompact ? compactHeight : height)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        VaseGlyph()
        VaseGlyph(isCompact: true)
    }
    .foregroundStyle(.ink)
    .padding()
    .background(.paper)
}
