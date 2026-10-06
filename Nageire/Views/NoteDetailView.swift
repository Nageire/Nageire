import SwiftUI

struct NoteDetailView: View {
    let note: NoteEntry
    /// The text being edited. Nil while the note is only read.
    @Binding var draft: String?
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let draft {
                NoteEditor(text: Binding { draft } set: { self.draft = $0 }) {
                    try model.editNote(note, text: draft)
                    self.draft = nil
                }
                // The note can leave the list under the edit, deleted on another device.
                .onDisappear { self.draft = nil }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: note.body)
                            .textSelection(.enabled)
                        if let updatedAt = note.updatedAt {
                            Text("Edited \(updatedAt, format: NoteEntry.dateFormat)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
        }
        .navigationTitle(note.createdAt.map { Text($0, format: NoteEntry.dateFormat) } ?? Text(verbatim: ""))
        .toolbarTitleDisplayMode(.inline)
        // In a narrow window the back button would leave the note with the edit neither saved nor cancelled.
        .navigationBarBackButtonHidden(draft != nil)
        .toolbar {
            if draft != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { draft = nil }
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    Button("Edit", systemImage: "pencil") { draft = note.editableText }
                }
            }
        }
    }
}
