import Foundation
import Testing
@testable import Nageire

@MainActor
struct GitHubSessionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let oauth = FakeOAuth()

    private func session(store: InMemoryTokenStore) -> GitHubSession {
        GitHubSession(store: store, oauth: oauth, now: { now })
    }

    @Test func returnsTheStoredAccessTokenWhileItIsValid() async throws {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(3600)))

        let token = try await session(store: store).accessToken()

        #expect(token == "access-old")
        #expect(oauth.refreshTokensUsed.isEmpty)
    }

    @Test func refreshesAnExpiredAccessTokenAndStoresTheNewTokens() async throws {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(-1)))

        let token = try await session(store: store).accessToken()

        #expect(token == "access-new")
        #expect(oauth.refreshTokensUsed == ["refresh-old"])
        #expect(store.tokens == TokenSet(accessToken: "access-new", accessTokenExpiresAt: now.addingTimeInterval(28800), refreshToken: "refresh-new"))
    }

    @Test func refreshesAnAccessTokenThatExpiresWithinAMinute() async throws {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(30)))

        #expect(try await session(store: store).accessToken() == "access-new")
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(-1)))
        let session = session(store: store)

        async let first = session.accessToken()
        async let second = session.accessToken()

        #expect(try await [first, second] == ["access-new", "access-new"])
        #expect(oauth.refreshTokensUsed == ["refresh-old"])
    }

    @Test func aRejectedRefreshDeletesTheTokensAndReportsSignedOut() async {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(-1)))
        oauth.refreshResult = .failure(OAuthError.rejected("bad_refresh_token"))
        let session = session(store: store)
        var signOuts = 0
        session.onSignOut = { signOuts += 1 }

        await #expect(throws: SessionError.signedOut) {
            try await session.accessToken()
        }
        #expect(store.tokens == nil)
        #expect(signOuts == 1)
    }

    @Test func signingOutWhileARefreshIsInFlightLeavesNoTokensBehind() async {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(-1)))
        let session = session(store: store)

        let request = Task { try await session.accessToken() }
        while oauth.refreshTokensUsed.isEmpty {
            await Task.yield()
        }
        session.signOut()
        _ = await request.result

        #expect(store.tokens == nil)
        #expect(!session.hasTokens)
    }

    @Test func aNetworkFailureDuringRefreshKeepsTheTokens() async {
        let tokens = TokenSet.sample(accessTokenExpiresAt: now.addingTimeInterval(-1))
        let store = InMemoryTokenStore(tokens: tokens)
        oauth.refreshResult = .failure(URLError(.notConnectedToInternet))
        let session = session(store: store)
        var signOuts = 0
        session.onSignOut = { signOuts += 1 }

        await #expect(throws: URLError.self) {
            try await session.accessToken()
        }
        #expect(store.tokens == tokens)
        #expect(signOuts == 0)
    }

    @Test func askingForATokenWithoutStoredTokensReportsSignedOut() async {
        await #expect(throws: SessionError.signedOut) {
            try await session(store: InMemoryTokenStore()).accessToken()
        }
    }

    @Test func startingWithAGrantStoresTokensWithAnAbsoluteExpiryDate() throws {
        let store = InMemoryTokenStore()

        try session(store: store).start(with: .sample)

        #expect(store.tokens?.accessTokenExpiresAt == now.addingTimeInterval(28800))
    }

    @Test func aRefusedTokenIsRefreshedEvenThoughItHasNotExpired() async throws {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(3600)))

        #expect(try await session(store: store).accessToken(replacing: "access-old") == "access-new")
    }

    @Test func aRefusedTokenThatWasAlreadyReplacedDoesNotRefreshAgain() async throws {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(3600)))

        #expect(try await session(store: store).accessToken(replacing: "access-before-old") == "access-old")
        #expect(oauth.refreshTokensUsed.isEmpty)
    }

    @Test func concurrentCallersAllSeeSignedOutWhenTheSharedRefreshIsRejected() async {
        let store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(-1)))
        oauth.refreshResult = .failure(OAuthError.rejected("bad_refresh_token"))
        let session = session(store: store)

        async let first = failure(of: session)
        async let second = failure(of: session)

        #expect(await [first, second] == [.signedOut, .signedOut])
    }

    private func failure(of session: GitHubSession) async -> SessionError? {
        do {
            _ = try await session.accessToken()
            return nil
        } catch {
            return error as? SessionError
        }
    }
}
