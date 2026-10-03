import SwiftUI

/// The text field for a new note, shown as the detail column of a wide window and in a sheet over a narrow one.
struct ComposeView: View {
    /// Changes each time the user asks for a new note, which puts the cursor in the field even when it is already showing.
    let focusRequest: Int
    var onSaved: () -> Void = {}

    @Environment(AppModel.self) private var model
    // Stored outside the view so that a draft survives the app being closed before it is saved.
    @AppStorage("draft") private var draft = ""
    @FocusState private var isEditing: Bool
    @State private var saveFailed = false

    var body: some View {
        TextEditor(text: $draft)
            .focused($isEditing)
            .font(.body)
            .padding(.horizontal)
            .navigationTitle("New note")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.allSatisfy(\.isWhitespace))
                }
            }
            .onAppear { isEditing = true }
            .onChange(of: focusRequest) { isEditing = true }
            .alert("The note could not be saved", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            }
    }

    private func save() {
        do {
            try model.saveNote(body: draft)
            draft = ""
            onSaved()
        } catch {
            saveFailed = true
        }
    }
}
