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

    init(configuration: GitHubAppConfiguration, oauth: GitHubOAuth, api: GitHubAPI, outbox: NoteOutbox, library: NoteLibrary, session: GitHubSession, defaults: UserDefaults) {
        self.configuration = configuration
        self.oauth = oauth
        self.api = api
        self.outbox = outbox
        self.library = library
        self.session = session
        self.defaults = defaults

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
        library.notes(including: outbox.pending, unsent: outbox.changes)
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
            // The device's copy mirrors one repository, so the previous one's notes go.
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

    func deleteNote(_ note: NoteEntry) throws {
        try outbox.delete(note)
        Task { await outbox.send() }
    }

    /// Sends what is waiting, then brings the list in line with the repository.
    func syncNotes() async {
        await outbox.send()
        if let repository {
            await library.refresh(from: repository)
        }
    }

    private func clear() {
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
