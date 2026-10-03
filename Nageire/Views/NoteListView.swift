import SwiftUI

struct NoteListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var isComposing = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: "Nageire"))
                .navigationDestination(for: NoteEntry.self) { NoteDetailView(note: $0) }
                .searchable(text: $query)
                .refreshable { await model.syncNotes() }
                .safeAreaInset(edge: .bottom) { status }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New note", systemImage: "square.and.pencil") { isComposing = true }
                            .keyboardShortcut("n", modifiers: .command)
                    }
                }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await model.syncNotes()
            }
        }
        .sheet(isPresented: $isComposing) { ComposeView() }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
    }

    @ViewBuilder
    private var content: some View {
        let notes = model.notes(matching: query)
        if !notes.isEmpty {
            List(notes) { note in
                NavigationLink(value: note) { NoteRow(note: note) }
            }
        } else if query.isEmpty {
            ContentUnavailableView {
                Label("No notes yet", systemImage: "square.and.pencil")
            } actions: {
                Button("Write a note") { isComposing = true }
                    .buttonStyle(.borderedProminent)
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
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
