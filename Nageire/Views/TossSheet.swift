import SwiftUI

/// The screen for a new note: a sheet over a narrow window, and the detail column of a wide one.
struct TossSheet: View {
    /// Changes each time the user asks for a new note, which puts the cursor in the field even when it is already showing.
    let focusRequest: Int

    @Environment(AppModel.self) private var model
    // In a sheet there is something to close; in the detail column of a wide window there is not.
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss
    // Stored outside the view so that a draft survives the app being closed before it is saved.
    @AppStorage(AppModel.Keys.draft) private var draft = ""
    /// The time of the note being written. In a wide window the column stays up between notes, so it moves with each.
    @State private var openedAt = Date.now
    @State private var saveFailed = false

    var body: some View {
        NoteEditor(text: $draft, focusRequest: focusRequest)
            .background(.paper)
            .navigationTitle("New note")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .cancellationAction) {
                        // Closing keeps the draft.
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(openedAt, format: .dateTime.month().day().hour().minute())
                        .font(.footnote)
                        .foregroundStyle(.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: toss)
                    .buttonStyle(.primary(compact: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.allSatisfy(\.isWhitespace))
                }
            }
            .saveFailureAlert(isPresented: $saveFailed)
            .onChange(of: focusRequest) { openedAt = .now }
    }

    private func toss() {
        do {
            // The one animation the app owns: the sheet goes down and the row settles in at the top of the stream.
            try withAnimation(.spring(duration: 0.48)) {
                try model.saveNote(body: draft)
            }
            draft = ""
            openedAt = .now
            if isPresented {
                dismiss()
            }
        } catch {
            saveFailed = true
        }
    }
}

#Preview {
    NavigationStack {
        TossSheet(focusRequest: 0)
    }
    .sample(AppModel.sample())
}
