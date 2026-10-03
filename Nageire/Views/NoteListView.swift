import SwiftUI

struct NoteListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var query = ""
    @State private var selection: NoteEntry.ID?
    @State private var isComposingInSheet = false
    @State private var newNoteRequests = 0
    #if !os(macOS)
    @State private var isShowingSettings = false
    #endif

    /// A wide window shows the list and one note side by side, and writes in the place of the note.
    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        let notes = model.notes()
        NavigationSplitView {
            list(of: notes)
                .navigationTitle(Text(verbatim: "Nageire"))
                .navigationSplitViewColumnWidth(min: 240, ideal: 320)
                .searchable(text: $query)
                .refreshable { await model.syncNotes() }
                .safeAreaInset(edge: .bottom) { status }
                .toolbar {
                    #if !os(macOS)
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    }
                    #endif
                    ToolbarItem(placement: .primaryAction) {
                        Button("New note", systemImage: "square.and.pencil", action: startNewNote)
                    }
                }
        } detail: {
            if let selection, let note = notes.first(where: { $0.id == selection }) {
                NoteDetailView(note: note)
            } else if isWide {
                ComposeView(focusRequest: newNoteRequests)
            }
        }
        .focusedSceneValue(\.startNewNote, newNoteCommand)
        .task(id: scenePhase) {
            if scenePhase == .active {
                await model.syncNotes()
            }
        }
        // A window that grows wide gets the text field as its detail column, and the sheet
        // would show the same draft a second time.
        .onChange(of: isWide) {
            if isWide {
                isComposingInSheet = false
            }
        }
        .sheet(isPresented: $isComposingInSheet) {
            NavigationStack {
                ComposeView(focusRequest: newNoteRequests) { isComposingInSheet = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", role: .cancel) { isComposingInSheet = false }
                        }
                    }
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        #endif
    }

    @ViewBuilder
    private func list(of all: [NoteEntry]) -> some View {
        let notes = all.matching(query)
        if !notes.isEmpty {
            List(notes, selection: $selection) { note in
                NoteRow(note: note)
            }
        } else if query.isEmpty {
            ContentUnavailableView {
                Label("No notes yet", systemImage: "square.and.pencil")
            } actions: {
                // A wide window already shows the text field next to this.
                if !isWide {
                    Button("Write a note", action: startNewNote)
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private var status: some View {
        Group {
            if model.outbox.wasRefused {
                Label("Can't write to the repository. Check it in Settings.", systemImage: "exclamationmark.triangle")
            } else if model.library.lastRefreshFailed {
                Text("Could not load notes from GitHub.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(8)
    }

    /// Nil while the settings sheet covers the list, which disables the menu command instead of opening a sheet under a sheet.
    private var newNoteCommand: (() -> Void)? {
        #if !os(macOS)
        if isShowingSettings { return nil }
        #endif
        return startNewNote
    }

    private func startNewNote() {
        // With no note selected, the detail column of a wide window is the text field.
        selection = nil
        isComposingInSheet = !isWide
        newNoteRequests += 1
    }
}

private struct NoteRow: View {
    let note: NoteEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: note.body)
                .lineLimit(3)
            HStack(spacing: 8) {
                if let createdAt = note.createdAt {
                    Text(createdAt, format: NoteEntry.dateFormat)
                }
                if note.isPending {
                    Label("Unsent", systemImage: "arrow.up.circle")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct NoteDetailView: View {
    let note: NoteEntry

    var body: some View {
        ScrollView {
            Text(verbatim: note.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(note.createdAt.map { Text($0, format: NoteEntry.dateFormat) } ?? Text(verbatim: ""))
        .toolbarTitleDisplayMode(.inline)
    }
}
