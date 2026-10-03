import SwiftUI

struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    // Stored outside the view so that a draft survives the app being closed before it is saved.
    @AppStorage("draft") private var draft = ""
    @FocusState private var isEditing: Bool
    @State private var isShowingSettings = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .focused($isEditing)
                .font(.body)
                .padding(.horizontal)
                .safeAreaInset(edge: .bottom) { status }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(draft.allSatisfy(\.isWhitespace))
                    }
                }
        }
        .onAppear { isEditing = true }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await model.outbox.send()
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .alert("The note could not be saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private var status: some View {
        Group {
            if model.outbox.wasRefused {
                Label("Can't write to the repository. Check it in Settings.", systemImage: "exclamationmark.triangle")
            } else if model.outbox.pendingCount > 0 {
                Text("Unsent notes: \(model.outbox.pendingCount)")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(8)
    }

    private func save() {
        do {
            try model.saveNote(body: draft)
            draft = ""
        } catch {
            saveFailed = true
        }
    }
}
