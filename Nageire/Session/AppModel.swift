import Foundation
import Observation

@Observable
final class AppModel {
    let configuration: GitHubAppConfiguration
    let oauth: GitHubOAuth
    let api: GitHubAPI
    let outbox: NoteOutbox
    private let session: GitHubSession
    private let defaults: UserDefaults

    private(set) var isSignedIn: Bool
    private(set) var accountLogin: String?
    private(set) var repository: Repository?

    init(configuration: GitHubAppConfiguration, oauth: GitHubOAuth, api: GitHubAPI, outbox: NoteOutbox, session: GitHubSession, defaults: UserDefaults) {
        self.configuration = configuration
        self.oauth = oauth
        self.api = api
        self.outbox = outbox
        self.session = session
        self.defaults = defaults

        isSignedIn = session.hasTokens
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
        self.repository = repository
        defaults.set(repository.fullName, forKey: Keys.repository)
        outbox.destination = repository
        // Notes refused by the previous repository are waiting for this one.
        Task { await outbox.send() }
    }

    func signOut() {
        session.signOut()
    }

    /// Saves the note on the device and starts sending it. Returns once it is saved; sending never holds up writing.
    func saveNote(body: String) throws {
        try outbox.add(body: body)
        Task { await outbox.send() }
    }

    private func clear() {
        isSignedIn = false
        accountLogin = nil
        repository = nil
        outbox.destination = nil
        defaults.removeObject(forKey: Keys.accountLogin)
        defaults.removeObject(forKey: Keys.repository)
    }

    private enum Keys {
        static let accountLogin = "accountLogin"
        static let repository = "repository"
    }
}

extension AppModel {
    static func live() -> AppModel {
        let configuration = GitHubAppConfiguration(bundle: .main)
        let transport = URLSessionTransport()
        let oauth = GitHubOAuthClient(clientID: configuration.clientID, transport: transport)
        let session = GitHubSession(store: KeychainTokenStore(), oauth: oauth)
        let api = GitHubAPIClient(transport: transport, session: session)
        return AppModel(
            configuration: configuration,
            oauth: oauth,
            api: api,
            outbox: NoteOutbox(store: FileNoteStore(directory: .applicationSupportDirectory.appending(path: "Notes")), api: api),
            session: session,
            defaults: .standard
        )
    }
}
