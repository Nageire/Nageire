import SwiftUI

/// The three steps of signing in. GitHub's pages do not say that installing follows authorizing,
/// so the whole path is laid out before it starts, and shown again with the step being done.
struct StepList: View {
    /// The step being done, from 1. Nil before the first starts, when every step is still ahead.
    var current: Int?

    /// The circle grows with the numeral inside it, which would otherwise outgrow it at the accessibility sizes.
    @ScaledMetric(relativeTo: .footnote) private var diameter: CGFloat = 26

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 16) {
            step(1, "Enter a code on GitHub")
            step(2, "Authorize Nageire")
            step(3, "Install it on the repository for your notes")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        let isLater = current.map { number > $0 } ?? false
        let numeral = Text(number, format: .number)
            .font(.footnote.weight(.semibold))
            .frame(width: diameter, height: diameter)
        return GridRow {
            // An outline while an earlier step is still being done, the ink fill otherwise.
            if isLater {
                numeral
                    .foregroundStyle(.ink2)
                    .hairlineBorder(.circle)
            } else {
                numeral
                    .foregroundStyle(.paper)
                    .background(.ink, in: .circle)
            }
            Text(text)
                .foregroundStyle(isLater ? Color.ink2 : .ink)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 32) {
        StepList()
        StepList(current: 1)
    }
    .foregroundStyle(.ink)
    .padding(Spacing.gutter)
    .background(.paper)
}
