import SwiftUI

/// The line above a note's text: when it was written, when it was edited, and whether GitHub has it.
struct NoteHeader: View {
    let note: NoteEntry

    var body: some View {
        // 10月3日 9:12 · 昨日 18:40 に編集 · ✓, with the parts the note has. The state is always there and last.
        HStack(spacing: 6) {
            if let createdAt = note.createdAt {
                Text(createdAt, format: .dateTime.month().day().hour().minute())
                separator
            }
            if let updatedAt = note.updatedAt {
                Text("Edited \(dayAndTime(updatedAt))")
                separator
            }
            if note.isPending {
                UnsentMark()
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityLabel(Text("Sent"))
            }
        }
        .font(.footnote)
        .foregroundStyle(.ink2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }

    /// 昨日 18:40 for a day close by, the date otherwise, so that an edit of today reads as such.
    private func dayAndTime(_ date: Date) -> Text {
        switch DayGroup.Label(date) {
        case .today: Text("Today \(date, format: .dateTime.hour().minute())")
        case .yesterday: Text("Yesterday \(date, format: .dateTime.hour().minute())")
        case .day, .undated: Text(date, format: .dateTime.month().day().hour().minute())
        }
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
