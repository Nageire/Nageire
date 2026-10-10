import Foundation
import Network
import Observation

@Observable
final class AppModel {
    let configuration: GitHubAppConfiguration
    let oauth: GitHubOAuth
    let api: GitHubAPI
    let outbox: NoteOutbox
    let library: NoteLibrary
    private let session: GitHubSession
    /// Where the account and the repository are kept, and what the views keep their own settings in.
    let defaults: UserDefaults

    private(set) var isSignedIn: Bool
    private(set) var accountLogin: String?
    private(set) var repository: Repository?
    /// When GitHub last took a note or a change from this device. Nil before the first.
    private(set) var lastSentAt: Date?
    /// The note whose deletion waits for the undo window to close. Out of `notes()` meanwhile.
    var pendingDeletion: NoteEntry? { deletion?.note }
    /// Set when the deletion could not be recorded on the device once its window closed; the note is back in the list.
    var deletionFailed = false
    /// Set when an edit could not be written to the device; the text stays in the editor.
    var editFailed = false
    /// Whether the app is in front, where the undo bar can be seen. The window runs only then,
    /// so that the bar never goes away unseen.
    var isInFront = true {
        didSet {
            updateUndoWindow()
            // The app put away is one of the moments an edit goes to GitHub.
            if !isInFront, sendAfterPause != nil {
                sendChanges()
            }
        }
    }

    /// Photos, and the notes that link to them, wait for Wi-Fi. Off by default, as the switch in Settings is.
    var sendsPhotosOnWiFiOnly: Bool {
        didSet {
            defaults.set(sendsPhotosOnWiFiOnly, forKey: Keys.sendsPhotosOnWiFiOnly)
            updatePhotoHold()
        }
    }
    /// How large a photo is kept and sent.
    var photoSize: PhotoSize {
        didSet { defaults.set(photoSize.rawValue, forKey: Keys.photoSize) }
    }
    /// The name of the note the draft becomes, given when its first file is attached, so that the file has the note's folder.
    private(set) var draftNoteName: String? {
        didSet {
            defaults.set(draftNoteName, forKey: Keys.draftNoteName)
            outbox.draftPath = draftEntry?.path
        }
    }
    /// The note the draft becomes, for its files. Nil until a file is attached to the draft.
    var draftEntry: NoteEntry? {
        draftNoteName.map { NoteEntry(path: Note(fileName: $0, contents: "").repositoryPath, contents: "", isPending: true) }
    }
    /// The device is on a network that costs by the byte: cellular, or a phone's hotspot. Nil until the network is first known,
    /// which holds the photos as a metered network does, so that a send at launch does not beat the first answer.
    var isOnMeteredNetwork: Bool? {
        didSet { updatePhotoHold() }
    }

    private let undoWindow: Duration
    /// How long typing may pause before the changes on the device go to GitHub as one commit.
    private let sendDelay: Duration
    /// How long typing may pause before the text goes to the device. A write per key costs the keystroke a few
    /// milliseconds of parsing and listing, so the keys of one burst are written together.
    private let writeDelay: Duration
    private var deletion: PendingDeletion?
    /// Sends when the pause is over, unless a change restarts it or a send comes first.
    private var sendAfterPause: Task<Void, Never>?
    /// The latest text typed, not yet on the device, and the task that writes it when the typing pauses.
    private var unwritten: (note: NoteEntry, text: String)?
    private var writeAfterPause: Task<Void, Never>?
    /// The window's undo manager, which reaches the pending deletion through Command-Z and the shake.
    private weak var undoManager: UndoManager?

    init(
        configuration: GitHubAppConfiguration,
        oauth: GitHubOAuth,
        api: GitHubAPI,
        outbox: NoteOutbox,
        library: NoteLibrary,
        session: GitHubSession,
        defaults: UserDefaults,
        undoWindow: Duration = .seconds(10),
        sendDelay: Duration = .seconds(30),
        writeDelay: Duration = .milliseconds(300)
    ) {
        self.configuration = configuration
        self.oauth = oauth
        self.api = api
        self.outbox = outbox
        self.library = library
        self.session = session
        self.defaults = defaults
        self.undoWindow = undoWindow
        self.sendDelay = sendDelay
        self.writeDelay = writeDelay

        isSignedIn = session.hasTokens
        lastSentAt = defaults.object(forKey: Keys.lastSentAt) as? Date
        sendsPhotosOnWiFiOnly = defaults.bool(forKey: Keys.sendsPhotosOnWiFiOnly)
        photoSize = defaults.string(forKey: Keys.photoSize).flatMap(PhotoSize.init) ?? .standard
        draftNoteName = defaults.string(forKey: Keys.draftNoteName)
        outbox.draftPath = draftEntry?.path
        if isSignedIn {
            accountLogin = defaults.string(forKey: Keys.accountLogin)
            if let fullName = defaults.string(forKey: Keys.repository) {
                repository = Repository(fullName: fullName)
                outbox.destination = repository
            }
        } else {
            // The Keychain item does not travel to a restored device while UserDefaults does,
            // so a selection can outlive its tokens. Without tokens it belongs to nobody.
            clear()
        }
        session.onSignOut = { [weak self] in self?.clear() }
        outbox.onSent = { [weak self, library] in
            library.add($0)
            self?.recordSend()
        }
        outbox.onChanged = { [weak self, library] in
            library.apply($0)
            self?.recordSend()
        }
        updatePhotoHold()
    }

    private func updatePhotoHold() {
        let holds = sendsPhotosOnWiFiOnly && isOnMeteredNetwork != false
        guard holds != outbox.holdsPhotos else { return }
        outbox.holdsPhotos = holds
        // The photos let go are sent now, not at the next note.
        if !holds {
            Task { await outbox.send() }
        }
    }

    /// Follows the network the device is on, for as long as the app runs.
    func watchNetwork() async {
        for await path in NWPathMonitor() where path.isExpensive != isOnMeteredNetwork {
            isOnMeteredNetwork = path.isExpensive
        }
    }

    private func recordSend() {
        lastSentAt = .now
        defaults.set(lastSentAt, forKey: Keys.lastSentAt)
    }

    /// The notes for the list, newest first: what GitHub holds and what is still waiting to be sent.
    func notes() -> [NoteEntry] {
        library.notes(including: outbox.pending, unsent: outbox.changes).filter { $0.id != pendingDeletion?.id }
    }

    /// The file an image line of the note links to, if the device has it.
    func attachment(of note: NoteEntry, linked link: String) -> Data? {
        guard let path = note.attachmentPath(linked: link) else { return nil }
        return try? library.attachment(at: path)
    }

    /// The model of the sign-in screen, which hands its tokens to this app.
    func makeSignInModel() -> SignInModel {
        SignInModel(flow: DeviceFlow(oauth: oauth), onAuthorized: completeSignIn)
    }

    func completeSignIn(with grant: TokenGrant) throws {
        try session.start(with: grant)
        isSignedIn = true
    }

    /// Fetches the signed-in user's login name. A failure keeps the name from the last successful fetch.
    func refreshAccount() async {
        guard let login = try? await api.currentUserLogin() else { return }
        accountLogin = login
        defaults.set(login, forKey: Keys.accountLogin)
    }

    func select(_ repository: Repository) {
        if repository != self.repository {
            // The device's copy mirrors one repository, so the previous one's notes go. A deletion
            // still in its window goes with them: recorded, it would be applied to this repository.
            undoDeletion()
            library.removeAll()
        }
        self.repository = repository
        defaults.set(repository.fullName, forKey: Keys.repository)
        outbox.destination = repository
        // Notes refused by the previous repository are waiting for this one.
        Task { await syncNotes() }
    }

    func signOut() {
        session.signOut()
    }

    /// Saves the note on the device and starts sending it. Returns once it is saved; sending never holds up writing.
    func saveNote(body: String) throws {
        try outbox.add(body: body, named: draftNoteName)
        draftNoteName = nil
        sendChanges()
    }

    /// Reduces the photo to the size Settings gives, keeps it beside the note, and returns the line that links it.
    /// A nil note is the draft, which is given its note's name with its first file.
    /// Throws `CancellationError` when the draft was saved or emptied while the photo was being reduced: its line has no draft to go into.
    func attachFile(_ contents: Data, named name: String?, to note: NoteEntry?) async throws -> String {
        if note == nil, draftNoteName == nil {
            draftNoteName = outbox.nameNewNote()
        }
        let target = note ?? draftEntry
        let photo = try await Photo.jpeg(from: contents, longSide: photoSize.longSide)
        guard let target, note != nil || target == draftEntry else { throw CancellationError() }
        return try outbox.attach(photo, named: Photo.fileName(for: name, takenAt: .now), to: target)
    }

    /// Lets go of the draft's note and its files once the draft is emptied, so that the next note is named when it is written.
    func discardDraftFiles() {
        guard draftNoteName != nil else { return }
        try? outbox.discardDraftFiles()
        draftNoteName = nil
    }

    /// Changes the note. The text goes to the device as soon as the typing pauses, and GitHub gets one commit
    /// when the note is closed, another is selected, the app leaves the front, or the typing pauses for
    /// `sendDelay`, whichever comes first. A note emptied is not written: it keeps its last text, as a new
    /// note is not sent while it is whitespace.
    func editNote(_ note: NoteEntry, text: String) {
        guard !text.allSatisfy(\.isWhitespace) else { return }
        unwritten = (note, text)
        writeAfterPause?.cancel()
        writeAfterPause = Task(name: "write-after-pause") { [weak self, writeDelay] in
            do {
                try await Task.sleep(for: writeDelay)
            } catch {
                // Cancelled: another key restarted the pause, or a send wrote first.
                return
            }
            // Cancelled between the wake and this turn of the main actor, by a key or a send.
            guard !Task.isCancelled else { return }
            self?.writeUnwritten()
        }
        sendAfterPause?.cancel()
        sendAfterPause = Task(name: "send-after-pause") { [weak self, sendDelay] in
            do {
                try await Task.sleep(for: sendDelay)
            } catch {
                // Cancelled: another change restarted the pause, or a send came first.
                return
            }
            // Cancelled between the wake and this turn of the main actor, by a change or a send.
            guard !Task.isCancelled else { return }
            self?.sendAfterPause = nil
            self?.writeUnwritten()
            await self?.outbox.send()
        }
    }

    /// Sends what waits, now. Every send of the model goes through here or `syncNotes`, so a send always ends the pauses.
    func sendChanges() {
        endPauses()
        Task { await outbox.send() }
    }

    /// Ends the pauses: the text waiting goes to the device, and the send that was to follow is the caller's.
    private func endPauses() {
        sendAfterPause?.cancel()
        sendAfterPause = nil
        writeUnwritten()
    }

    /// Writes the latest text to the device, if there is one waiting.
    private func writeUnwritten() {
        writeAfterPause?.cancel()
        writeAfterPause = nil
        guard let (note, text) = unwritten else { return }
        unwritten = nil
        do {
            try outbox.edit(note, text: text)
        } catch {
            editFailed = true
        }
    }

    /// Takes the note out of the list and opens the undo window; the deletion is recorded and sent when the window closes.
    /// A deletion still in its window is recorded at once, so that one bar stands for one note.
    func deleteNote(_ note: NoteEntry, undoManager: UndoManager? = nil) {
        guard deletion?.note.id != note.id else { return }
        queuePendingDeletion()
        deletion = PendingDeletion(note: note, timeLeft: undoWindow)
        self.undoManager = undoManager
        undoManager?.registerUndo(withTarget: self) { model in model.undoDeletion() }
        undoManager?.setActionName(String(localized: "Delete"))
        updateUndoWindow()
    }

    /// Puts the note back. Nothing was recorded yet, so there is nothing to take back from the outbox.
    func undoDeletion() {
        guard deletion != nil else { return }
        closeUndoWindow()
    }

    private func queuePendingDeletion() {
        guard let note = deletion?.note else { return }
        closeUndoWindow()
        do {
            try outbox.delete(note)
            sendChanges()
        } catch {
            deletionFailed = true
        }
    }

    private func closeUndoWindow() {
        deletion?.run?.task.cancel()
        deletion = nil
        undoManager?.removeAllActions(withTarget: self)
        undoManager = nil
    }

    /// Runs the window while the app is in front and holds it otherwise, keeping the time it has left.
    private func updateUndoWindow() {
        guard var deletion else { return }
        if let run = deletion.run {
            run.task.cancel()
            deletion.timeLeft = max(.zero, deletion.timeLeft - run.since.duration(to: .now))
            deletion.run = nil
        }
        if isInFront {
            let task = Task(name: "undo-window") { [timeLeft = deletion.timeLeft] in
                do {
                    try await Task.sleep(for: timeLeft)
                } catch {
                    // Cancelled: the window is held, or was closed by an undo.
                    return
                }
                // Closed between the wake and this turn of the main actor, for another deletion.
                guard !Task.isCancelled else { return }
                queuePendingDeletion()
            }
            deletion.run = (task, .now)
        }
        self.deletion = deletion
    }

    /// Sends what is waiting, then brings the list in line with the repository.
    func syncNotes() async {
        endPauses()
        await outbox.send()
        if let repository {
            await library.refresh(from: repository)
        }
    }

    private func clear() {
        // A deletion still in its window stays on the device through the sign-out, as a recorded one does,
        // and so does an edit whose pause is still running.
        queuePendingDeletion()
        endPauses()
        isSignedIn = false
        accountLogin = nil
        repository = nil
        lastSentAt = nil
        outbox.destination = nil
        // Notes already on GitHub are fetched again after the next sign-in; unsent ones stay in the outbox.
        library.removeAll()
        defaults.removeObject(forKey: Keys.accountLogin)
        defaults.removeObject(forKey: Keys.repository)
        defaults.removeObject(forKey: Keys.lastSentAt)
    }

    /// The keys in `defaults`, the model's and the views'.
    enum Keys {
        static let accountLogin = "accountLogin"
        static let repository = "repository"
        /// The text of a new note not yet tossed, kept so that it survives a relaunch.
        static let draft = "draft"
        static let lastSentAt = "lastSentAt"
        /// The note body in the serif. The rest of the app stays in the sans.
        static let serifBody = "serifBody"
        static let sendsPhotosOnWiFiOnly = "sendsPhotosOnWiFiOnly"
        static let photoSize = "photoSize"
        /// The name of the note the draft becomes, kept with the draft.
        static let draftNoteName = "draftNoteName"
    }
}

/// A deletion in its undo window.
private struct PendingDeletion {
    let note: NoteEntry
    /// What the window has left, as of the moment it last ran or was held.
    var timeLeft: Duration
    /// The task sleeping through the window and when it began; nil while the app is not in front.
    var run: (task: Task<Void, Never>, since: ContinuousClock.Instant)?
}

extension AppModel {
    static func live() -> AppModel {
        let configuration = GitHubAppConfiguration(bundle: .main)
        let transport = URLSessionTransport()
        let oauth = GitHubOAuthClient(clientID: configuration.clientID, transport: transport)
        let session = GitHubSession(store: KeychainTokenStore(), oauth: oauth)
        let api = GitHubAPIClient(transport: transport, session: session)
        let store = FileNoteStore(directory: .applicationSupportDirectory.appending(path: "Notes"))
        let model = AppModel(
            configuration: configuration,
            oauth: oauth,
            api: api,
            outbox: NoteOutbox(store: store, api: api),
            library: NoteLibrary(store: store, api: api),
            session: session,
            defaults: .standard
        )
        Task(name: "network-watch") { await model.watchNetwork() }
        return model
    }
}
