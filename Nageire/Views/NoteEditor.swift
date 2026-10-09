import SwiftUI

/// The editor, shared by writing a new note and editing one. The button that saves a new note belongs to the sheet around it.
struct NoteEditor: View {
    @Binding var text: String
    /// Changes each time the cursor should go to the editor even though it is already showing.
    var focusRequest = 0
    /// The toss sheet is for writing and takes the keyboard as it appears; a note opens to be read, and a tap into the text takes it.
    var focusesOnAppear = true
    /// The note column on macOS centers its text at the reading width; the toss column keeps the gutter.
    var isNoteColumn = false
    /// Above the text, scrolling with it: the note's header.
    var header: AnyView?
    /// The file an image line links to, for its thumbnail. Nil while the device does not have the file.
    var attachment: (String) -> Data? = { _ in nil }

    @AppStorage(AppModel.Keys.serifBody) private var serifBody = false
    /// The cursor goes into the editor when it appears, and on each request after that.
    @State private var focusRequests = 0
    @State private var requests = EditorRequests()
    /// The text view has the keyboard. The Format menu acts only then, not while a search field has it.
    @State private var isFocused = false

    var body: some View {
        MarkdownTextView(text: $text, serif: serifBody, focusRequest: focusRequests, requests: requests, isFocused: $isFocused, isNoteColumn: isNoteColumn, header: header, attachment: attachment)
            .focusedSceneValue(\.editorRequests, isFocused ? requests : nil)
            .onAppear {
                if focusesOnAppear {
                    focusRequests += 1
                }
            }
            .onChange(of: focusRequest) { focusRequests += 1 }
    }
}

/// The way from the Format menu to the editor that has the focus. A class, so that the focused value compares by identity.
final class EditorRequests {
    /// The text view's coordinator, set when the view is made.
    weak var editor: MarkdownTextCoordinator?

    func request(_ command: EditorCommand) {
        editor?.perform(command)
    }
}

extension FocusedValues {
    /// Nil while no editor has the keyboard.
    @Entry var editorRequests: EditorRequests?
}

extension View {
    /// The one alert for a note that could not be written to the device, which the toss sheet and the note screen share.
    func saveFailureAlert(isPresented: Binding<Bool>) -> some View {
        alert("The note could not be saved", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        }
    }
}

#Preview {
    @Previewable @State var text = SampleData.notes()[4].editableText
    let note = SampleData.notes()[4]
    let model = AppModel.sample()
    NoteEditor(text: $text, focusesOnAppear: false, isNoteColumn: true, header: AnyView(NoteHeader(note: note).padding(.bottom, Spacing.headerGap))) { model.attachment(of: note, linked: $0) }
        .background(.paper)
}

#Preview("Serif, accessibility size") {
    @Previewable @State var text = SampleData.draft
    let model = AppModel.sample()
    NoteEditor(text: $text)
        .environment(\.dynamicTypeSize, .accessibility3)
        .background(.paper)
        .sample(model)
        .onAppear { model.defaults.set(true, forKey: AppModel.Keys.serifBody) }
}
