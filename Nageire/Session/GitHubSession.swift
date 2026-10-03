import Foundation

enum SessionError: Error, Equatable {
    case signedOut
}

/// Holds the user's tokens and hands out an access token that is valid at the time of the call.
final class GitHubSession {
    private let store: TokenStore
    private let oauth: GitHubOAuth
    private let now: () -> Date
    private var tokens: TokenSet?
    private var refreshTask: Task<String, Error>?

    /// Called whenever the tokens are discarded, whether the user asked for it or GitHub refused them.
    var onSignOut: () -> Void = {}

    init(store: TokenStore, oauth: GitHubOAuth, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.oauth = oauth
        self.now = now
        // TODO: Tell a Keychain read error apart from an empty Keychain before background sync lands.
        // A launch before the first unlock fails to read, and treating that as signed out
        // makes AppModel erase the saved account and repository.
        tokens = try? store.load()
    }

    var hasTokens: Bool {
        tokens != nil
    }

    func start(with grant: TokenGrant) throws {
        let tokens = TokenSet(grant, receivedAt: now())
        try store.save(tokens)
        self.tokens = tokens
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        try? store.delete()
        onSignOut()
    }

    /// - Parameter refused: An access token GitHub answered with 401. It is treated as expired whatever its expiry date says.
    func accessToken(replacing refused: String? = nil) async throws -> String {
        guard let tokens else {
            throw SessionError.signedOut
        }
        // The margin keeps a token from expiring between this check and its arrival at GitHub.
        if tokens.accessToken != refused, tokens.accessTokenExpiresAt > now().addingTimeInterval(60) {
            return tokens.accessToken
        }
        // A refresh token can be used once. Concurrent callers share one request,
        // because a second request with the same token would be refused and sign the user out.
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task {
            defer { refreshTask = nil }
            do {
                let renewed = TokenSet(try await oauth.refresh(refreshToken: tokens.refreshToken), receivedAt: now())
                // A sign-out during the request must win, or the response would bring the session back.
                try Task.checkCancellation()
                self.tokens = renewed
                // A failed write is not thrown: the caller's request can proceed with the token
                // in memory, and nothing the caller does would repair the Keychain.
                try? store.save(renewed)
                return renewed.accessToken
            } catch OAuthError.rejected {
                // Only an explicit refusal ends the session. A network failure leaves the tokens
                // in place so that opening the app offline does not force a new sign-in.
                signOut()
                throw SessionError.signedOut
            }
        }
        refreshTask = task
        return try await task.value
    }
}
