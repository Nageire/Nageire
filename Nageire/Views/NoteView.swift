import SwiftUI

/// One note, read and edited on one surface. There is nothing to save: the text is on the device as it is typed.
struct NoteView: View {
    let note: NoteEntry
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    /// The editor's text. Starts as the note's, and is not replaced by what a refresh brings while the note is open.
    @State private var text: String

    init(note: NoteEntry, onDelete: @escaping () -> Void) {
        self.note = note
        self.onDelete = onDelete
        _text = State(initialValue: note.editableText)
    }

    var body: some View {
        @Bindable var model = model
        NoteEditor(
            text: $text, focusesOnAppear: false, isNoteColumn: true,
            header: AnyView(NoteHeader(note: note).padding(.bottom, Spacing.headerGap)),
            attachment: { model.attachment(of: note, linked: $0) },
            attachFile: { try await model.attachFile($0, named: $1, to: note) }
        )
            .background(.paper)
            .onChange(of: text) { model.editNote(note, text: text) }
            // Closing the note, or opening another in its place, is one of the moments the edits go to GitHub.
            .onDisappear { model.sendChanges() }
            #if os(macOS)
            .navigationTitle(Text(verbatim: note.displayTitle))
            #else
            // The title is the first line of the text, which the screen already shows.
            .navigationTitle(Text(verbatim: ""))
            #endif
            .toolbarTitleDisplayMode(.inline)
            .saveFailureAlert(isPresented: $model.editFailed)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: text)
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

    /// The note's page on GitHub, on the default branch. Nil while GitHub does not have the note as it is shown.
    private var gitHubURL: URL? {
        guard !note.isPending, let repository = model.repository else { return nil }
        return URL(string: "https://github.com/\(repository.fullName)/blob/HEAD/")?.appending(path: note.path)
    }
}

#Preview {
    NavigationStack {
        NoteView(note: SampleData.notes()[4]) {}
    }
    .sample(AppModel.sample())
}
