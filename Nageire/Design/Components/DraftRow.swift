import SwiftUI

/// The note being written, at the top of the stream while its sheet is closed. Quiet: a word and the first line.
struct DraftRow: View {
    let text: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Spacing.rowGap) {
                Text("Draft")
                    .font(.footnote.weight(.semibold))
                Text(verbatim: NoteEntry(path: "", contents: text, isPending: true).displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    List {
        DraftRow(text: SampleData.draft) {}
            .listRowInsets(.stream)
            .listRowSeparatorTint(.hairline)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(.paper)
}
