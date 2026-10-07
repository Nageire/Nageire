import SwiftUI

/// One note, read and edited on one surface. Until phase 2 the edit is the plain text view behind an Edit button.
struct NoteView: View {
    let note: NoteEntry
    /// The text being edited. Nil while the note is only read.
    @Binding var draft: String?
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var saveFailed = false

    var body: some View {
        Group {
            if let draft {
                NoteEditor(text: Binding { draft } set: { self.draft = $0 })
                    // The note can leave the list under the edit, deleted on another device.
                    .onDisappear { self.draft = nil }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NoteHeader(note: note)
                        Text(verbatim: note.body)
                            .noteBodyStyle()
                            .foregroundStyle(.ink)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(macOS)
                    // The note column centers its text at a reading width.
                    .frame(maxWidth: 680)
                    .padding(.top, 28)
                    .padding(.horizontal, 48)
                    .frame(maxWidth: .infinity)
                    #else
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.rowPadding)
                    #endif
                }
            }
        }
        .background(.paper)
        #if os(macOS)
        .navigationTitle(Text(verbatim: note.displayTitle))
        #else
        // The title is the first line of the text, which the screen already shows.
        .navigationTitle(Text(verbatim: ""))
        #endif
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
                    Button("Edit", systemImage: "pencil") { draft = note.editableText }
                    ShareLink(item: note.body)
                    Menu("More", systemImage: "ellipsis") {
                        Button("Open on GitHub", systemImage: "arrow.up.right.square") {
                            if let url = gitHubURL { openURL(url) }
                        }
                        // While GitHub does not have the note as it is shown, its page is either absent or the text before the edit.
                        .disabled(gitHubURL == nil)
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                }
            }
        }
    }

    /// The note's page on GitHub, on the default branch. Nil while GitHub does not have the note as it is shown.
    private var gitHubURL: URL? {
        guard !note.isPending, let repository = model.repository else { return nil }
        return URL(string: "https://github.com/\(repository.fullName)/blob/HEAD/")?.appending(path: note.path)
    }
}

#Preview {
    NavigationStack {
        NoteView(note: SampleData.notes()[4], draft: .constant(nil)) {}
    }
    .sample(AppModel.sample())
}
