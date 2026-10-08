import SwiftUI

/// The line above a note's text: when it was written, when it was edited, and whether GitHub has it.
struct NoteHeader: View {
    let note: NoteEntry

    var body: some View {
        // 10月3日 9:12 · 昨日 18:40 に編集 · ✓, with the parts the note has. The state is always there and last.
        // Past the width, as at a large text size or in English, each part would wrap in a column of
        // its own, so the parts then go under one another, without the dots between them.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { parts(dotted: true) }
            VStack(alignment: .leading, spacing: 4) { parts(dotted: false) }
        }
        .font(.footnote)
        .foregroundStyle(.ink2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func parts(dotted: Bool) -> some View {
        if let createdAt = note.createdAt {
            Text(createdAt, format: .dateTime.month().day().hour().minute())
            if dotted { separator }
        }
        if let updatedAt = note.updatedAt {
            Text("Edited \(Text(dayAndTime: updatedAt))")
            if dotted { separator }
        }
        if note.isPending {
            UnsentMark()
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityLabel(Text("Sent"))
        }
    }

    private var separator: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(SampleData.notes().prefix(5)) { note in
            NoteHeader(note: note)
        }
    }
    .padding(Spacing.gutter)
    .background(.paper)
}

#Preview("Accessibility size") {
    NoteHeader(note: SampleData.notes().first { $0.updatedAt != nil }!)
        .environment(\.dynamicTypeSize, .accessibility5)
        .padding(Spacing.gutter)
        .background(.paper)
}
