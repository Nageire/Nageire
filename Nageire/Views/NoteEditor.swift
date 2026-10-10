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
    /// Keeps a file, from its bytes and its own name if it has one, and returns the line that links it. Nil where no file is added.
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
    @State private var isPickingFiles = false
    @State private var fileFailed = false
    /// The files over `Attachment.largeSize`, asked about one at a time.
    @State private var largeFiles: [IncomingFile] = []
    /// The files over `Attachment.maximumSize`, which are not kept, told about one at a time.
    @State private var refusedFiles: [IncomingFile] = []
    /// The files waiting to be kept, taken in order by one task at a time, so that a paste of ten is not read at once.
    @State private var queuedFiles: [IncomingFile] = []
    @State private var isKeepingFiles = false

    var body: some View {
        pickersAndAlerts(editor)
    }

    private var editor: some View {
        MarkdownTextView(
            text: $text, serif: serifBody, focusRequest: focusRequests, requests: requests, isFocused: $isFocused,
            isNoteColumn: isNoteColumn, header: header, attachment: attachment,
            canAddPhotos: attachFile != nil, canTakePhoto: attachFile != nil && CameraPicker.isAvailable, canAddFiles: attachFile != nil
        )
        .focusedSceneValue(\.editorRequests, isFocused ? requests : nil)
        .onAppear {
            if attachFile != nil {
                requests.addPhotos = { isPickingPhotos = true }
                requests.takePhoto = CameraPicker.isAvailable ? { isTakingPhoto = true } : nil
                requests.addFiles = { isPickingFiles = true }
                requests.receive = receive
            }
            if focusesOnAppear {
                focusRequests += 1
            }
        }
        .onChange(of: focusRequest) { focusRequests += 1 }
    }
}

extension NoteEditor {
    /// The pickers, the alerts, and the preview, apart from the body, which the compiler would otherwise check as one expression.
    fileprivate func pickersAndAlerts(_ content: some View) -> some View {
        content
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
                    await attach([{ (try await CameraPicker.jpeg(of: photo, metadata: metadata), nil) }], failed: $photoFailed)
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .alert("The photo could not be added", isPresented: $photoFailed) {
            Button("OK", role: .cancel) {}
        }
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            let files = urls.compactMap { try? IncomingFile(url: $0) }
            fileFailed = files.count < urls.count
            receive(files)
        }
        // The alert goes with the file it asked about, and the next file's comes up after it.
        .alert("Large file", isPresented: queueBinding($largeFiles), presenting: largeFiles.first) { file in
            Button("Add") { keep([file]) }
            Button("Cancel", role: .cancel) {}
        } message: { file in
            Text("\(file.name ?? "") is \(file.size.formatted(.byteCount(style: .file))). It will take a while to send and will make the repository larger.")
        }
        .alert("File too large", isPresented: queueBinding($refusedFiles, after: largeFiles), presenting: refusedFiles.first) { _ in
            Button("OK", role: .cancel) {}
        } message: { file in
            Text("GitHub takes files of up to \(Attachment.maximumSize.formatted(.byteCount(style: .file))). \(file.name ?? "") is \(file.size.formatted(.byteCount(style: .file))).")
        }
        .alert("The file could not be added", isPresented: $fileFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Presented while the queue has a file, after `before` is empty; closing it takes the file off, which brings up the next.
    private func queueBinding(_ queue: Binding<[IncomingFile]>, after before: [IncomingFile] = []) -> Binding<Bool> {
        Binding {
            before.isEmpty && !queue.wrappedValue.isEmpty
        } set: { isPresented in
            if !isPresented, !queue.wrappedValue.isEmpty {
                queue.wrappedValue.removeFirst()
            }
        }
    }

    /// Keeps the files that are small enough, asks about each large one, and tells of each that GitHub would refuse.
    private func receive(_ files: [IncomingFile]) {
        var fine: [IncomingFile] = []
        for file in files {
            switch Attachment.check(size: file.size, name: file.name) {
            case .fine: fine.append(file)
            case .large: largeFiles.append(file)
            case .tooLarge: refusedFiles.append(file)
            }
        }
        keep(fine)
    }

    /// Queues the files to be kept in the order they came. One task keeps them, the files queued together as one edit.
    private func keep(_ files: [IncomingFile]) {
        queuedFiles += files
        guard !isKeepingFiles else { return }
        isKeepingFiles = true
        Task {
            while !queuedFiles.isEmpty {
                let files = queuedFiles
                queuedFiles = []
                await attach(files.map { file in { (try await file.contents(), file.name) } }, failed: $fileFailed)
            }
            isKeepingFiles = false
        }
    }

    private func attach(_ items: [PhotosPickerItem]) async {
        await attach(items.map { item in
            {
                guard let photo = try await item.loadTransferable(type: PickedPhoto.self) else { throw PhotoError.unreadable }
                // A GIF is kept as it is, so it is checked for its size like any other file.
                guard Attachment.check(size: photo.contents.count, name: photo.name) == .fine else {
                    receive([IncomingFile(contents: photo.contents, name: photo.name)])
                    return nil
                }
                return (photo.contents, photo.name)
            }
        }, failed: $photoFailed)
    }

    /// Keeps the files in the order they came and puts their lines in at the caret together, as one edit.
    /// Each is read only when the one before is kept, so that ten photos are never in memory at once. A file handed
    /// on elsewhere gives nil.
    private func attach(_ files: [() async throws -> (contents: Data, name: String?)?], failed: Binding<Bool>) async {
        guard let attachFile else { return }
        var lines: [String] = []
        for file in files {
            do {
                guard let (contents, name) = try await file() else { continue }
                lines.append(try await attachFile(contents, name))
            } catch is CancellationError {
                // The draft was saved or emptied meanwhile; the file has no line to go into.
            } catch {
                failed.wrappedValue = true
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
    /// Opens the file picker for the editor, from the Format menu and the accessory bar.
    var addFiles: (() -> Void)?
    /// Takes the files pasted or dropped into the editor.
    var receive: (([IncomingFile]) -> Void)?

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
