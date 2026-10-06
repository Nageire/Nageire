import SwiftUI

struct NoteDetailView: View {
    let note: NoteEntry
    /// The text being edited. Nil while the note is only read.
    @Binding var draft: String?
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model
    @State private var saveFailed = false

    var body: some View {
        Group {
            if let draft {
                NoteEditor(text: Binding { draft } set: { self.draft = $0 })
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
        .saveFailureAlert(isPresented: $saveFailed)
        .toolbar {
            if let draft {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { self.draft = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try model.editNote(note, text: draft)
                            self.draft = nil
                        } catch {
                            saveFailed = true
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.allSatisfy(\.isWhitespace))
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
