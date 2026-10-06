import SwiftUI

/// The screen for a new note: a sheet over a narrow window, and the detail column of a wide one.
struct TossSheet: View {
    /// Changes each time the user asks for a new note, which puts the cursor in the field even when it is already showing.
    let focusRequest: Int
    var onSaved: () -> Void = {}

    @Environment(AppModel.self) private var model
    // Stored outside the view so that a draft survives the app being closed before it is saved.
    @AppStorage("draft") private var draft = ""

    var body: some View {
        NoteEditor(text: $draft, focusRequest: focusRequest) {
            try model.saveNote(body: draft)
            draft = ""
            onSaved()
        }
        .navigationTitle("New note")
        .toolbarTitleDisplayMode(.inline)
    }
}
