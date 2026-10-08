import SwiftUI

struct StreamView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager
    @State private var query = ""
    @State private var selection: NoteEntry.ID?
    @State private var isComposingInSheet = false
    @State private var newNoteRequests = NewNoteRequests()
    @AppStorage(AppModel.Keys.draft) private var draft = ""
    /// The text of the note being edited in the detail column. Nil while no note is being edited.
    @State private var editDraft: String?
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #else
    @State private var isShowingSettings = false
    #endif

    /// A wide window shows the list and one note side by side, and writes in the place of the note.
    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        @Bindable var model = model
        let notes = model.notes()
        NavigationSplitView {
            list(of: notes)
                // The empty states would otherwise end with their content, and the stream's paper with them.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.surfaceStream)
                // Above the list and not in it: the refusal has to show over an empty stream too,
                // which is where a refused deletion leaves it.
                .safeAreaInset(edge: .top) {
                    if model.outbox.wasRefused {
                        RefusedBanner(openSettings: showSettings)
                            .padding(.horizontal, Spacing.listGutter)
                            .padding(.top, 8)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if model.pendingDeletion != nil {
                        UndoBar(undo: model.undoDeletion)
                            .padding(.horizontal, Spacing.listGutter)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.default, value: model.pendingDeletion?.id)
                .navigationTitle(Text(verbatim: "Nageire"))
                #if os(macOS)
                // The toolbar's own search field takes so much room that the new-note button
                // is pushed into the overflow menu; in the sidebar it sits above the list it filters.
                .searchable(text: $query, placement: .sidebar)
                #else
                .searchable(text: $query)
                #endif
                .refreshable { await model.syncNotes() }
                .toolbar {
                    #if os(macOS)
                    if !isWide {
                        ToolbarItem(placement: .primaryAction) { TossButton(requests: newNoteRequests, isEnabled: canStartNewNote) }
                    }
                    #else
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape", action: showSettings)
                    }
                    // The bottom bar: the search field and the toss button in one glass group, within
                    // reach of the thumb. In a wide window the button belongs to the detail column.
                    if !isWide {
                        DefaultToolbarItem(kind: .search, placement: .bottomBar)
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) { TossButton(requests: newNoteRequests, isEnabled: canStartNewNote) }
                    }
                    #endif
                }
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            if let selection, let note = notes.first(where: { $0.id == selection }) {
                NoteView(note: note, draft: $editDraft) { delete(note) }
                    .toolbar {
                        // In a wide window the button belongs to the detail column: the sidebar's
                        // share of the toolbar is too narrow for it and drops it into the overflow menu.
                        // It goes with the note: while the column is the toss screen itself, that
                        // screen's own button is the one to press.
                        if isWide {
                            ToolbarItem(placement: .primaryAction) { TossButton(requests: newNoteRequests, isEnabled: canStartNewNote) }
                        }
                    }
            } else if isWide {
                TossSheet(focusRequest: newNoteRequests.count)
            }
        }
        .focusedSceneValue(\.newNoteRequests, canStartNewNote ? newNoteRequests : nil)
        .onChange(of: newNoteRequests.count) { startNewNote() }
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
                TossSheet(focusRequest: newNoteRequests.count)
            }
            .presentationDragIndicator(.visible)
        }
        #if !os(macOS)
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        #endif
        .alert("The note could not be deleted", isPresented: $model.deletionFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func delete(_ note: NoteEntry) {
        model.deleteNote(note, undoManager: undoManager)
        if selection == note.id {
            selection = nil
        }
    }

    @ViewBuilder
    private func list(of all: [NoteEntry]) -> some View {
        let notes = all.matching(query)
        if !notes.isEmpty || (!draft.isEmpty && query.isEmpty) {
            // One flat list of rows, so that the list can tell its rows apart by their ids alone.
            // The day's heading is a row and not a section header, which the two platforms
            // inset differently from the rows under it.
            List(selection: $selection) {
                if !draft.isEmpty, query.isEmpty {
                    DraftRow(text: draft) { newNoteRequests.request() }
                        .listRowInsets(.stream)
                        .listRowSeparatorTint(.hairline)
                        // The list draws a rule above its first row, which the day headings hide and this row would show under the title.
                        .listRowSeparator(.hidden, edges: .top)
                        .listRowBackground(Color.clear)
                        .selectionDisabled()
                }
                ForEach(StreamRow.rows(of: notes)) { row in
                    switch row {
                    case .heading(let group):
                        DayHeader(label: group.label())
                            .listRowInsets(.streamHeader)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .selectionDisabled()
                    case .note(let note):
                        NoteRow(note: note)
                            .listRowInsets(.stream)
                            .listRowSeparatorTint(.hairline)
                            .listRowBackground(rowBackground(for: note))
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(note) }
                            }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(note) }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(macOS)
            .onDeleteCommand {
                if let note = notes.first(where: { $0.id == selection }) {
                    delete(note)
                }
            }
            #endif
            // In a wide window the list sits beside the note being edited, and selecting
            // another note there would discard the edit without a word.
            .disabled(editDraft != nil)
        } else if query.isEmpty {
            EmptyState()
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    /// The selected row on macOS is a wash of the accent; the system's highlight would be the accent itself.
    private func rowBackground(for note: NoteEntry) -> some View {
        RoundedRectangle(cornerRadius: Radius.input)
            .fill(selection == note.id ? Color.accentWash : .clear)
            .padding(.horizontal, 8)
    }

    private func showSettings() {
        #if os(macOS)
        openSettings()
        #else
        isShowingSettings = true
        #endif
    }

    /// False while the settings sheet covers the list or a note is being edited, which disables the menu command instead of opening a sheet under a sheet.
    private var canStartNewNote: Bool {
        #if !os(macOS)
        if isShowingSettings { return false }
        #endif
        return editDraft == nil
    }

    private func startNewNote() {
        // With no note selected, the detail column of a wide window is the text field.
        selection = nil
        isComposingInSheet = !isWide
    }
}

/// The button for a new note: the vase alone, as the compose button of the system's apps is an icon alone.
private struct TossButton: View {
    let requests: NewNoteRequests
    let isEnabled: Bool

    var body: some View {
        Button { requests.request() } label: {
            VaseGlyph()
                .padding(.horizontal, 2)
        }
        .buttonStyle(.glassProminent)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("New note"))
        .help(Text("New note"))
    }
}

/// Counts the times a new note was asked for in a window. The stream opens the sheet or the
/// detail column at each, and the command menu reaches it through the focused scene. A class,
/// so that the focused value compares by identity; a closure there could not be compared at all.
@Observable
final class NewNoteRequests {
    private(set) var count = 0

    func request() {
        count += 1
    }
}

/// What the stream lists: a heading for each day, then that day's notes.
private enum StreamRow: Identifiable {
    case heading(DayGroup)
    case note(NoteEntry)

    var id: String {
        switch self {
        case .heading(let group): group.day.map { "day-\($0.timeIntervalSinceReferenceDate)" } ?? "undated"
        case .note(let note): note.id
        }
    }

    static func rows(of notes: [NoteEntry]) -> [StreamRow] {
        notes.groupedByDay().flatMap { [.heading($0)] + $0.notes.map(StreamRow.note) }
    }
}
