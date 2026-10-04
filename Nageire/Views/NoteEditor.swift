import SwiftUI

/// The text field and the Save button, shared by writing a new note and editing one.
struct NoteEditor: View {
    @Binding var text: String
    /// Changes each time the cursor should go to the field even though it is already showing.
    var focusRequest = 0
    let save: () throws -> Void

    @FocusState private var isEditing: Bool
    @State private var saveFailed = false

    var body: some View {
        TextEditor(text: $text)
            .focused($isEditing)
            .font(.body)
            .padding(.horizontal)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try save()
                        } catch {
                            saveFailed = true
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.allSatisfy(\.isWhitespace))
                }
            }
            .onAppear { isEditing = true }
            .onChange(of: focusRequest) { isEditing = true }
            .alert("The note could not be saved", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            }
    }
}
