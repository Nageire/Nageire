import SwiftUI

/// The text field, shared by writing a new note and editing one. The button that saves belongs to the screen around it.
struct NoteEditor: View {
    @Binding var text: String
    /// Changes each time the cursor should go to the field even though it is already showing.
    var focusRequest = 0

    @FocusState private var isEditing: Bool

    var body: some View {
        TextEditor(text: $text)
            .focused($isEditing)
            .font(.body)
            .foregroundStyle(.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal)
            .onAppear { isEditing = true }
            .onChange(of: focusRequest) { isEditing = true }
    }
}

extension View {
    /// The one alert for a note that could not be written to the device, which the toss sheet and the note screen share.
    func saveFailureAlert(isPresented: Binding<Bool>) -> some View {
        alert("The note could not be saved", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        }
    }
}
