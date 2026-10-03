import SwiftUI

struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    // Stored outside the view so that a draft survives the app being closed before it is saved.
    @AppStorage("draft") private var draft = ""
    @FocusState private var isEditing: Bool
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .focused($isEditing)
                .font(.body)
                .padding(.horizontal)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(draft.allSatisfy(\.isWhitespace))
                    }
                }
        }
        .onAppear { isEditing = true }
        .alert("The note could not be saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    private func save() {
        do {
            try model.saveNote(body: draft)
            draft = ""
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
