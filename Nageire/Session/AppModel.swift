import Foundation
import Observation

@Observable
final class AppModel {
    let configuration: GitHubAppConfiguration
    let oauth: GitHubOAuth
    let api: GitHubAPI
    private let session: GitHubSession
    private let defaults: UserDefaults

    private(set) var isSignedIn: Bool
    private(set) var accountLogin: String?
    private(set) var repository: Repository?

    init(configuration: GitHubAppConfiguration, oauth: GitHubOAuth, api: GitHubAPI, session: GitHubSession, defaults: UserDefaults) {
        self.configuration = configuration
        self.oauth = oauth
        self.api = api
        self.session = session
        self.defaults = defaults

        isSignedIn = session.hasTokens
        if isSignedIn {
            accountLogin = defaults.string(forKey: Keys.accountLogin)
            // TODO: Detect a selected repository the GitHub App can no longer reach when notes are first written to it.
            // Nothing checks at launch that the installation still covers the repository.
            if let fullName = defaults.string(forKey: Keys.repository) {
                repository = Repository(fullName: fullName)
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
    }

    func signOut() {
        session.signOut()
    }

    private func clear() {
        isSignedIn = false
        accountLogin = nil
        repository = nil
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
        return AppModel(
            configuration: configuration,
            oauth: oauth,
            api: GitHubAPIClient(transport: transport, session: session),
            session: session,
            defaults: .standard
        )
    }
}
