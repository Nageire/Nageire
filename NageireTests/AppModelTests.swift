import Foundation
import Testing
@testable import Nageire

@MainActor
struct AppModelTests {
    private let store = InMemoryTokenStore()
    private let api = FakeAPI()
    private let defaults: UserDefaults

    init() {
        let suite = "AppModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func model() -> AppModel {
        let oauth = FakeOAuth()
        return AppModel(
            configuration: GitHubAppConfiguration(clientID: "client-id", slug: "nageire"),
            oauth: oauth,
            api: api,
            session: GitHubSession(store: store, oauth: oauth),
            defaults: defaults
        )
    }

    @Test func startsSignedOutWithoutStoredTokens() {
        let model = model()

        #expect(!model.isSignedIn)
        #expect(model.repository == nil)
    }

    @Test func completingSignInStoresTheTokensAndSignsIn() throws {
        let model = model()

        try model.completeSignIn(with: .sample)

        #expect(model.isSignedIn)
        #expect(store.tokens?.accessToken == "access-new")
    }

    @Test func aRelaunchRestoresTheSessionAccountAndRepositoryWithoutTheNetwork() async throws {
        let first = model()
        try first.completeSignIn(with: .sample)
        await first.refreshAccount()
        first.select(Repository(owner: "octocat", name: "notes"))
        api.login = .failure(URLError(.notConnectedToInternet))

        let relaunched = model()
        await relaunched.refreshAccount()

        #expect(relaunched.isSignedIn)
        #expect(relaunched.accountLogin == "octocat")
        #expect(relaunched.repository == Repository(owner: "octocat", name: "notes"))
    }

    @Test func signingOutRemovesTheTokensTheAccountAndTheRepository() async throws {
        let model = model()
        try model.completeSignIn(with: .sample)
        await model.refreshAccount()
        model.select(Repository(owner: "octocat", name: "notes"))

        model.signOut()

        #expect(!model.isSignedIn)
        #expect(model.accountLogin == nil)
        #expect(model.repository == nil)
        #expect(store.tokens == nil)
        let relaunched = self.model()
        #expect(!relaunched.isSignedIn)
        #expect(relaunched.accountLogin == nil)
        #expect(relaunched.repository == nil)
    }

    @Test func aSelectionLeftBehindWithoutTokensIsDiscardedAtLaunch() throws {
        let first = model()
        try first.completeSignIn(with: .sample)
        first.select(Repository(owner: "octocat", name: "notes"))
        store.tokens = nil

        let relaunched = model()
        try relaunched.completeSignIn(with: .sample)

        #expect(relaunched.repository == nil)
    }
}
