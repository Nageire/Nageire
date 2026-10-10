import PhotosUI
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
    /// Keeps a photo, from its bytes and its own name if it has one, and returns the line that links it. Nil where no photo is added.
    var attachFile: ((Data, String?) async throws -> String)?

    @AppStorage(AppModel.Keys.serifBody) private var serifBody = false
    /// The cursor goes into the editor when it appears, and on each request after that.
    @State private var focusRequests = 0
    @State private var requests = EditorRequests()
    /// The text view has the keyboard. The Format menu acts only then, not while a search field has it.
    @State private var isFocused = false
    @State private var isPickingPhotos = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var isTakingPhoto = false
    @State private var photoFailed = false

    var body: some View {
        MarkdownTextView(
            text: $text, serif: serifBody, focusRequest: focusRequests, requests: requests, isFocused: $isFocused,
            isNoteColumn: isNoteColumn, header: header, attachment: attachment,
            canAddPhotos: attachFile != nil, canTakePhoto: attachFile != nil && CameraPicker.isAvailable
        )
        .focusedSceneValue(\.editorRequests, isFocused ? requests : nil)
        .onAppear {
            if attachFile != nil {
                requests.addPhotos = { isPickingPhotos = true }
                requests.takePhoto = CameraPicker.isAvailable ? { isTakingPhoto = true } : nil
            }
            if focusesOnAppear {
                focusRequests += 1
            }
        }
        .onChange(of: focusRequest) { focusRequests += 1 }
        // The photo keeps its own encoding: the app makes the JPEG itself, at the size Settings gives.
        .photosPicker(isPresented: $isPickingPhotos, selection: $pickedPhotos, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickedPhotos) {
            guard !pickedPhotos.isEmpty else { return }
            let items = pickedPhotos
            pickedPhotos = []
            Task { await attach(items) }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { photo, metadata in
                Task {
                    await attach([{ (try await CameraPicker.jpeg(of: photo, metadata: metadata), nil) }])
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .alert("The photo could not be added", isPresented: $photoFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func attach(_ items: [PhotosPickerItem]) async {
        await attach(items.map { item in
            {
                guard let photo = try await item.loadTransferable(type: PickedPhoto.self) else { throw PhotoError.unreadable }
                return (photo.contents, photo.name)
            }
        })
    }

    /// Keeps the photos in the order they were picked and puts their lines in at the caret together, as one edit.
    /// Each is read only when the one before is kept, so that ten photos are never in memory at once.
    private func attach(_ photos: [() async throws -> (contents: Data, name: String?)]) async {
        guard let attachFile else { return }
        var lines: [String] = []
        for photo in photos {
            do {
                let (contents, name) = try await photo()
                lines.append(try await attachFile(contents, name))
            } catch is CancellationError {
                // The draft was saved or emptied meanwhile; the photo has no line to go into.
            } catch {
                photoFailed = true
            }
        }
        requests.editor?.insert(lines)
    }
}

/// A photo from the library as the system hands it over: the file, with the name it has in the library.
private struct PickedPhoto: Transferable {
    let contents: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            // The file is the system's and is gone after this returns.
            PickedPhoto(contents: try Data(contentsOf: received.file), name: received.file.lastPathComponent)
        }
    }
}

/// The way from the Format menu to the editor that has the focus. A class, so that the focused value compares by identity.
final class EditorRequests {
    /// The text view's coordinator, set when the view is made.
    weak var editor: MarkdownTextCoordinator?
    /// Opens the photo library for the editor, from the Format menu and the accessory bar. Nil where the editor adds no photo.
    var addPhotos: (() -> Void)?
    /// Opens the camera for the editor, from the accessory bar.
    var takePhoto: (() -> Void)?

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
