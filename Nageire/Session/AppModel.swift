import Foundation
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
    /// Whether the app is in front, where the undo bar can be seen. The window runs only then,
    /// so that the bar never goes away unseen.
    var isInFront = true {
        didSet { updateUndoWindow() }
    }

    private let undoWindow: Duration
    private var deletion: PendingDeletion?
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
        undoWindow: Duration = .seconds(10)
    ) {
        self.configuration = configuration
        self.oauth = oauth
        self.api = api
        self.outbox = outbox
        self.library = library
        self.session = session
        self.defaults = defaults
        self.undoWindow = undoWindow

        isSignedIn = session.hasTokens
        lastSentAt = defaults.object(forKey: Keys.lastSentAt) as? Date
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
    }

    private func recordSend() {
        lastSentAt = .now
        defaults.set(lastSentAt, forKey: Keys.lastSentAt)
    }

    /// The notes for the list, newest first: what GitHub holds and what is still waiting to be sent.
    func notes() -> [NoteEntry] {
        library.notes(including: outbox.pending, unsent: outbox.changes).filter { $0.id != pendingDeletion?.id }
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
        try outbox.add(body: body)
        Task { await outbox.send() }
    }

    /// Changes the note on the device and starts sending the change, as with a new note.
    func editNote(_ note: NoteEntry, text: String) throws {
        try outbox.edit(note, text: text)
        Task { await outbox.send() }
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
            Task { await outbox.send() }
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
        await outbox.send()
        if let repository {
            await library.refresh(from: repository)
        }
    }

    private func clear() {
        // A deletion still in its window stays on the device through the sign-out, as a recorded one does.
        queuePendingDeletion()
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
        return AppModel(
            configuration: configuration,
            oauth: oauth,
            api: api,
            outbox: NoteOutbox(store: store, api: api),
            library: NoteLibrary(store: store, api: api),
            session: session,
            defaults: .standard
        )
    }
}
