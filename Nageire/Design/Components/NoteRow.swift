import SwiftUI

/// A note in the stream: its title, up to two lines of its text, and when it was written.
struct NoteRow: View {
    let note: NoteEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.rowGap) {
            Text(verbatim: note.displayTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(.ink)
                .lineLimit(1)
            if !note.excerpt.isEmpty {
                Text(verbatim: note.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.ink2)
                    .lineLimit(2)
            }
            // A file the app did not write can have no time; its row then has no third line.
            if note.createdAt != nil || note.attachmentCount > 0 || note.isPending {
                HStack(spacing: 10) {
                    if let createdAt = note.createdAt {
                        Text(createdAt, format: .dateTime.hour().minute())
                    }
                    if note.attachmentCount > 0 {
                        Label {
                            Text(note.attachmentCount, format: .number)
                        } icon: {
                            Image(systemName: "paperclip")
                        }
                        .labelStyle(.tight)
                        .accessibilityLabel(Text("\(note.attachmentCount) attachments"))
                    }
                    if note.isPending {
                        UnsentMark()
                    }
                }
                .font(.footnote)
                .foregroundStyle(.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    List(SampleData.notes()) { note in
        NoteRow(note: note)
            .listRowInsets(.stream)
            .listRowSeparatorTint(.hairline)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(.paper)
}
