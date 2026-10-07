import Foundation
import Testing
@testable import Nageire

@MainActor
struct AppModelTests {
    private let store = InMemoryTokenStore()
    private let notes = InMemoryNoteStore()
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
            outbox: NoteOutbox(store: notes, api: api),
            library: NoteLibrary(store: notes, api: api),
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

    // The limit ends a wait for a send that never comes. It is not one minute: on a hosted runner the
    // simulator's services start while the tests run, and they have held the main actor for longer
    // than that, which failed this test while it was only waiting for its turn.
    @Test(.timeLimit(.minutes(5))) func choosingARepositorySendsTheNotesThatWereWaitingForOne() async throws {
        let model = model()
        try model.completeSignIn(with: .sample)
        try model.outbox.add(body: "Written before a repository was chosen")

        model.select(Repository(owner: "octocat", name: "notes"))
        while model.outbox.pendingCount > 0 {
            await Task.yield()
        }

        #expect(api.createFileAttempts.map(\.repository) == ["octocat/notes"])
    }

    @Test(.timeLimit(.minutes(5))) func savingANoteKeepsItOnTheDeviceSendsItToTheChosenRepositoryAndRecordsTheSend() async throws {
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))

        try model.saveNote(body: "Hello")
        #expect(model.outbox.pendingCount == 1)
        #expect(model.lastSentAt == nil)
        while model.outbox.pendingCount > 0 {
            await Task.yield()
        }

        #expect(api.createFileAttempts.count == 1)
        #expect(model.lastSentAt != nil)
        #expect(self.model().lastSentAt == model.lastSentAt)
    }

    @Test func notesStayOnTheDeviceUnsentAfterSigningOut() async throws {
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        model.signOut()

        try model.outbox.add(body: "Hello")
        await model.outbox.send()

        #expect(model.outbox.pendingCount == 1)
        #expect(api.createFileAttempts.isEmpty)
    }

    @Test func aSavedNoteIsInTheListAtOnceAsUnsentAndStaysThereOnceSent() async throws {
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await model.syncNotes()

        try model.saveNote(body: "Hello")
        #expect(model.notes().map(\.isPending) == [true])
        await model.syncNotes()

        #expect(model.notes().map(\.body) == ["Hello"])
        #expect(model.notes().map(\.isPending) == [false])
    }

    @Test func syncingListsTheNotesTheRepositoryHolds() async throws {
        api.remoteNotes = .success(["notes/2026/10/2026-10-03T135812Z-a1b2.md": "---\ncreated: 2026-10-03T22:58:12+09:00\n---\n\nFrom another device\n"])
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))

        await model.syncNotes()

        #expect(model.notes().map(\.body) == ["From another device"])
    }

    @Test func choosingAnotherRepositoryDropsTheNotesOfThePreviousOne() async throws {
        api.remoteNotes = .success(["notes/2026/10/2026-10-03T135812Z-a1b2.md": "First repository\n"])
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await model.syncNotes()
        api.remoteNotes = .failure(URLError(.notConnectedToInternet))

        model.select(Repository(owner: "octocat", name: "journal"))

        #expect(model.notes().isEmpty)
    }

    @Test func signingOutDropsTheFetchedNotesAndKeepsTheUnsentOnes() async throws {
        api.remoteNotes = .success(["notes/2026/10/2026-10-03T135812Z-a1b2.md": "Fetched\n"])
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await model.syncNotes()
        api.createFileResults = [.failure(URLError(.notConnectedToInternet))]
        try model.outbox.add(body: "Unsent")
        await model.outbox.send()

        model.signOut()

        #expect(model.notes().map(\.body) == ["Unsent"])
        #expect(notes.files.isEmpty)
    }
    private let remotePath = "notes/2026/10/2026-10-03T135812Z-a1b2.md"

    private func modelListingOneRemoteNote() async throws -> AppModel {
        api.remoteNotes = .success([remotePath: "---\ncreated: 2026-10-03T22:58:12+09:00\n---\n\nFrom another device\n"])
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await model.syncNotes()
        return model
    }

    @Test func anEditedNoteShowsItsNewTextAtOnceAsUnsentAndThenReachesGitHub() async throws {
        let model = try await modelListingOneRemoteNote()

        try model.editNote(try #require(model.notes().first), text: "Edited")

        #expect(model.notes().map(\.body) == ["Edited"])
        #expect(model.notes().map(\.isPending) == [true])
        #expect(model.lastSentAt == nil)

        await model.syncNotes()

        #expect(model.notes().map(\.body) == ["Edited"])
        #expect(model.notes().map(\.isPending) == [false])
        #expect(try api.remoteNotes.get()[remotePath]?.hasSuffix("\n\nEdited\n") == true)
        #expect(model.lastSentAt != nil)
    }

    @Test func aDeletedNoteLeavesTheListAtOnceAndIsThenRemovedFromGitHub() async throws {
        let model = try await modelListingOneRemoteNote()

        try model.deleteNote(try #require(model.notes().first))

        #expect(model.notes().isEmpty)

        await model.syncNotes()

        #expect(model.notes().isEmpty)
        #expect(try api.remoteNotes.get().isEmpty)
    }

    @Test func anEditStillUnsentAtSignOutStaysOnTheDevice() async throws {
        let model = try await modelListingOneRemoteNote()
        api.changeResults = [.failure(URLError(.notConnectedToInternet))]
        try model.editNote(try #require(model.notes().first), text: "Edited")
        await model.outbox.send()

        model.signOut()

        #expect(model.outbox.pendingCount == 1)
    }
}
