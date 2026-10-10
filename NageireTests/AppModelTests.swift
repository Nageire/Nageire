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

    private func model(undoWindow: Duration = .seconds(10), sendDelay: Duration = .seconds(30)) -> AppModel {
        model(undoWindow: undoWindow, sendDelay: sendDelay, writeDelay: .zero)
    }

    private func model(undoWindow: Duration, sendDelay: Duration, writeDelay: Duration) -> AppModel {
        let oauth = FakeOAuth()
        return AppModel(
            configuration: GitHubAppConfiguration(clientID: "client-id", slug: "nageire"),
            oauth: oauth,
            api: api,
            outbox: NoteOutbox(store: notes, api: api),
            library: NoteLibrary(store: notes, api: api),
            session: GitHubSession(store: store, oauth: oauth),
            defaults: defaults,
            undoWindow: undoWindow,
            sendDelay: sendDelay,
            writeDelay: writeDelay
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
        await outboxToDrain(of: model)

        #expect(api.createFileAttempts.map(\.repository) == ["octocat/notes"])
    }

    @Test(.timeLimit(.minutes(5))) func savingANoteKeepsItOnTheDeviceSendsItToTheChosenRepositoryAndRecordsTheSend() async throws {
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))

        try model.saveNote(body: "Hello")
        #expect(model.outbox.pendingCount == 1)
        #expect(model.lastSentAt == nil)
        await outboxToDrain(of: model)

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

    /// The window runs on the clock, so the tests that let it close give it a short one and wait here.
    private func undoWindowToClose(of model: AppModel) async {
        while model.pendingDeletion != nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// A send runs on its own task, so the tests that expect one wait here for the outbox to empty.
    private func outboxToDrain(of model: AppModel) async {
        while model.outbox.pendingCount > 0 {
            await Task.yield()
        }
    }

    /// The text typed goes to the device after a pause, which the tests set to nothing and wait out here.
    private func writeToLand(of model: AppModel) async {
        while model.outbox.changes.isEmpty {
            await Task.yield()
        }
    }

    private func modelListingOneRemoteNote(undoWindow: Duration = .seconds(10), sendDelay: Duration = .seconds(30)) async throws -> AppModel {
        try await modelListing([remotePath: "---\ncreated: 2026-10-03T22:58:12+09:00\n---\n\nFrom another device\n"], undoWindow: undoWindow, sendDelay: sendDelay)
    }

    private func modelListing(_ remoteNotes: [String: String], undoWindow: Duration = .seconds(10), sendDelay: Duration = .seconds(30)) async throws -> AppModel {
        api.remoteNotes = .success(remoteNotes)
        let model = model(undoWindow: undoWindow, sendDelay: sendDelay)
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await model.syncNotes()
        return model
    }

    @Test func anEditedNoteShowsItsNewTextAtOnceAsUnsentAndReachesGitHubWithTheNextSend() async throws {
        let model = try await modelListingOneRemoteNote()

        model.editNote(try #require(model.notes().first), text: "Edited")
        await writeToLand(of: model)

        #expect(model.notes().map(\.body) == ["Edited"])
        #expect(model.notes().map(\.isPending) == [true])
        #expect(model.lastSentAt == nil)

        await model.syncNotes()

        #expect(model.notes().map(\.body) == ["Edited"])
        #expect(model.notes().map(\.isPending) == [false])
        #expect(try api.remoteNotes.get()[remotePath]?.hasSuffix("\n\nEdited\n") == true)
        #expect(model.lastSentAt != nil)
    }

    @Test(.timeLimit(.minutes(5))) func editsTypedWithinThePauseReachGitHubAsOneCommitAfterIt() async throws {
        let model = try await modelListingOneRemoteNote(sendDelay: .milliseconds(100))
        let note = try #require(model.notes().first)

        model.editNote(note, text: "Edit")
        model.editNote(try #require(model.notes().first), text: "Edited")
        await writeToLand(of: model)

        #expect(model.notes().map(\.isPending) == [true])
        await outboxToDrain(of: model)

        #expect(try api.remoteNotes.get()[remotePath]?.hasSuffix("\n\nEdited\n") == true)
        #expect(api.writeFileAttempts.count == 1)
    }

    @Test func anEmptiedNoteKeepsItsTextOnTheDevice() async throws {
        let model = try await modelListingOneRemoteNote()
        let note = try #require(model.notes().first)

        model.editNote(note, text: "Edited")
        await writeToLand(of: model)
        model.editNote(try #require(model.notes().first), text: " \n")
        model.sendChanges()

        #expect(model.notes().map(\.body) == ["Edited"])
    }

    @Test(.timeLimit(.minutes(5))) func leavingTheFrontSendsAnEditBeforeThePauseIsOver() async throws {
        let model = try await modelListingOneRemoteNote(sendDelay: .seconds(3600))

        model.editNote(try #require(model.notes().first), text: "Edited")
        model.isInFront = false

        await outboxToDrain(of: model)
        #expect(try api.remoteNotes.get()[remotePath]?.hasSuffix("\n\nEdited\n") == true)
    }

    @Test(.timeLimit(.minutes(5))) func aDeletedNoteLeavesTheListAtOnceAndIsRemovedFromGitHubOnceItsUndoWindowCloses() async throws {
        let model = try await modelListingOneRemoteNote(undoWindow: .milliseconds(50))
        let note = try #require(model.notes().first)

        model.deleteNote(note)

        #expect(model.notes().isEmpty)
        #expect(model.pendingDeletion == note)
        #expect(model.outbox.changes.isEmpty)

        await undoWindowToClose(of: model)
        await model.syncNotes()

        #expect(model.notes().isEmpty)
        #expect(try api.remoteNotes.get().isEmpty)
    }

    @Test func undoingADeletionWithinItsWindowPutsTheNoteBackWithNothingRecorded() async throws {
        let model = try await modelListingOneRemoteNote()
        let note = try #require(model.notes().first)
        model.deleteNote(note)

        model.undoDeletion()

        #expect(model.notes() == [note])
        #expect(model.pendingDeletion == nil)
        #expect(model.outbox.changes.isEmpty)
        await model.syncNotes()
        #expect(api.deleteFileAttempts.isEmpty)
    }

    @Test(.timeLimit(.minutes(5))) func theUndoWindowWaitsWhileTheAppIsNotInFront() async throws {
        let model = try await modelListingOneRemoteNote(undoWindow: .milliseconds(50))
        // Offline, so that the deletion stays recorded once the window closes.
        api.changeResults = [.failure(URLError(.notConnectedToInternet))]
        model.deleteNote(try #require(model.notes().first))

        model.isInFront = false
        try await Task.sleep(for: .milliseconds(200))

        #expect(model.pendingDeletion != nil)
        #expect(model.outbox.changes.isEmpty)

        model.isInFront = true
        await undoWindowToClose(of: model)

        #expect(model.outbox.changes.map(\.path) == [remotePath])
    }

    @Test func deletingASecondNoteRecordsTheFirstDeletionAtOnce() async throws {
        let otherPath = "notes/2026/10/2026-10-04T080000Z-c3d4.md"
        let model = try await modelListing([remotePath: "First\n", otherPath: "Second\n"])
        api.changeResults = [.failure(URLError(.notConnectedToInternet))]
        let first = try #require(model.notes().first { $0.path == remotePath })
        let second = try #require(model.notes().first { $0.path == otherPath })

        model.deleteNote(first)
        model.deleteNote(second)

        #expect(model.notes().isEmpty)
        #expect(model.pendingDeletion == second)
        #expect(model.outbox.changes.map(\.path) == [remotePath])
        model.undoDeletion()
    }

    @Test func aDeletionStillInItsWindowIsUndoneWhenAnotherRepositoryIsChosen() async throws {
        let model = try await modelListingOneRemoteNote()
        model.deleteNote(try #require(model.notes().first))

        model.select(Repository(owner: "octocat", name: "journal"))
        await model.syncNotes()

        #expect(model.pendingDeletion == nil)
        #expect(model.outbox.changes.isEmpty)
        #expect(api.deleteFileAttempts.isEmpty)
    }

    @Test func aDeletionStillInItsWindowAtSignOutIsRecordedAndStaysOnTheDevice() async throws {
        let model = try await modelListingOneRemoteNote()
        model.deleteNote(try #require(model.notes().first))

        model.signOut()

        #expect(model.pendingDeletion == nil)
        #expect(model.outbox.changes.map(\.path) == [remotePath])
    }

    @Test(.timeLimit(.minutes(5))) func theUndoManagerUndoesADeletionWithinItsWindowAndNotAfterIt() async throws {
        let model = try await modelListingOneRemoteNote(undoWindow: .milliseconds(50))
        api.changeResults = [.failure(URLError(.notConnectedToInternet))]
        let note = try #require(model.notes().first)
        let undoManager = UndoManager()

        model.deleteNote(note, undoManager: undoManager)
        #expect(undoManager.canUndo)
        undoManager.undo()

        #expect(model.notes() == [note])
        #expect(!undoManager.canUndo)

        model.deleteNote(note, undoManager: undoManager)
        await undoWindowToClose(of: model)
        undoManager.undo()

        #expect(model.notes().isEmpty)
        #expect(model.outbox.changes.map(\.path) == [remotePath])
    }

    @Test func anEditStillUnsentAtSignOutStaysOnTheDevice() async throws {
        let model = try await modelListingOneRemoteNote()
        api.changeResults = [.failure(URLError(.notConnectedToInternet))]
        model.editNote(try #require(model.notes().first), text: "Edited")
        await writeToLand(of: model)
        await model.outbox.send()

        model.signOut()

        #expect(model.outbox.pendingCount == 1)
    }

    @Test func anImageLineOfANoteReadsItsFileFromTheDeviceAndALinkElsewhereReadsNothing() throws {
        let model = model()
        let note = NoteEntry(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", contents: "a\n", isPending: false)
        _ = try model.outbox.attach(Data("jpeg".utf8), named: "IMG_0421.jpeg", to: note)

        #expect(model.attachment(of: note, linked: "2026-10-03T135812Z-a1b2/IMG_0421.jpeg") == Data("jpeg".utf8))
        #expect(model.attachment(of: note, linked: "https://example.com/IMG_0421.jpeg") == nil)
        #expect(model.attachment(of: note, linked: "2026-10-03T135812Z-a1b2/other.jpeg") == nil)
    }

    @Test func withTheSwitchOnPhotosWaitOffWiFiAndGoWhenWiFiReturns() async throws {
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await outboxToDrain(of: model)
        model.isOnMeteredNetwork = true
        model.sendsPhotosOnWiFiOnly = true
        try model.saveNote(body: "Photo")
        let note = try #require(model.outbox.pending.first)
        let entry = NoteEntry(path: note.repositoryPath, contents: note.contents, isPending: true)
        try model.outbox.edit(entry, text: "Photo\n\n" + model.outbox.attach(Data("jpeg".utf8), named: "IMG.jpeg", to: entry))
        await model.outbox.send()

        #expect(model.outbox.pendingCount == 2)
        #expect(self.model().sendsPhotosOnWiFiOnly)

        model.isOnMeteredNetwork = false
        await outboxToDrain(of: model)

        #expect(api.committedPaths.suffix(2) == ["\(entry.folderPath)/IMG.jpeg", entry.path])
        #expect(model.outbox.pendingCount == 0)
    }

    @Test func withTheSwitchOnPhotosWaitUntilTheNetworkIsFirstKnown() {
        let model = model()
        model.sendsPhotosOnWiFiOnly = true

        #expect(model.outbox.holdsPhotos)

        model.isOnMeteredNetwork = false

        #expect(!model.outbox.holdsPhotos)
    }

    @Test func theDraftsFirstPhotoGivesItTheNoteItBecomesWhichSurvivesARelaunch() async throws {
        let model = model()
        let line = try await model.attachFile(pngData(width: 300, height: 200), named: "IMG_0421.HEIC", to: nil)
        let draft = try #require(model.draftEntry)

        #expect(line == "![IMG_0421.jpeg](\(draft.folderName)/IMG_0421.jpeg)")
        #expect(model.outbox.pendingCount == 0)
        let relaunched = self.model()
        try relaunched.completeSignIn(with: .sample)
        relaunched.select(Repository(owner: "octocat", name: "notes"))
        await relaunched.outbox.send()
        #expect(relaunched.draftEntry == draft)
        #expect(relaunched.attachment(of: draft, linked: "\(draft.folderName)/IMG_0421.jpeg") != nil)

        try model.saveNote(body: "庭\n\n" + line)

        #expect(model.outbox.pending.map(\.repositoryPath) == [draft.path])
        #expect(model.draftEntry == nil)
        #expect(model.attachment(of: draft, linked: "\(draft.folderName)/IMG_0421.jpeg") != nil)
    }

    @Test func aPhotoIsKeptAtTheSizeSettingsGives() async throws {
        let model = model()
        model.photoSize = .large
        let note = NoteEntry(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", contents: "a\n", isPending: false)

        _ = try await model.attachFile(pngData(width: 5000, height: 1000), named: "wide.png", to: note)

        let photo = try #require(model.attachment(of: note, linked: "2026-10-03T135812Z-a1b2/wide.jpeg"))
        #expect(try pixelSize(of: photo).width == 4096)
        #expect(self.model().photoSize == .large)
    }

    @Test func anEmptiedDraftLetsGoOfTheNoteItWasToBecomeAndItsFiles() async throws {
        let model = model()
        _ = try await model.attachFile(pngData(width: 300, height: 200), named: "IMG.png", to: nil)
        let draft = try #require(model.draftEntry)

        model.discardDraftFiles()

        #expect(model.draftEntry == nil)
        #expect(self.model().draftEntry == nil)
        #expect(model.outbox.draftPath == nil)
        #expect(model.attachment(of: draft, linked: "\(draft.folderName)/IMG.jpeg") == nil)
    }

    @Test func aFileThatIsNotAPhotoIsKeptAsItIsAndLinked() async throws {
        let model = model()
        let note = NoteEntry(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", contents: "a\n", isPending: false)
        let gif = pngData(width: 4000, height: 10)

        let pdfLine = try await model.attachFile(Data("%PDF".utf8), named: "scan.pdf", to: note)
        let gifLine = try await model.attachFile(gif, named: "loop.gif", to: note)

        #expect(pdfLine == "[scan.pdf](2026-10-03T135812Z-a1b2/scan.pdf)")
        #expect(gifLine == "![loop.gif](2026-10-03T135812Z-a1b2/loop.gif)")
        #expect(model.attachment(of: note, linked: "2026-10-03T135812Z-a1b2/scan.pdf") == Data("%PDF".utf8))
        #expect(model.attachment(of: note, linked: "2026-10-03T135812Z-a1b2/loop.gif") == gif)
    }

    @Test func openingANoteWithAFileAnotherDeviceSentFetchesItAndTellsTheEditor() async throws {
        let path = "notes/2026/10/2026-10-03T135812Z-a1b2.md"
        api.remoteNotes = .success([path: "![a.jpeg](2026-10-03T135812Z-a1b2/a.jpeg)\n", "notes/2026/10/2026-10-03T135812Z-a1b2/a.jpeg": "a"])
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await model.syncNotes()
        let note = try #require(model.notes().first)

        await model.fetchAttachments(of: note)

        #expect(model.attachmentArrivals == 1)
        #expect(model.attachment(of: note, linked: "2026-10-03T135812Z-a1b2/a.jpeg") == Data("a".utf8))
    }

    @Test func aFileAnotherDeviceSentIsRemovedOnlyWhenTheNoteLinkedItBeforeTheEdit() async throws {
        let path = "notes/2026/10/2026-10-03T135812Z-a1b2.md"
        let folder = "notes/2026/10/2026-10-03T135812Z-a1b2"
        api.remoteNotes = .success([
            path: "---\n---\n\n![a.jpeg](2026-10-03T135812Z-a1b2/a.jpeg)\n",
            "\(folder)/a.jpeg": "a",
            // Sent by a device whose edit linking it has not arrived.
            "\(folder)/b.jpeg": "b",
        ])
        let model = model()
        try model.completeSignIn(with: .sample)
        model.select(Repository(owner: "octocat", name: "notes"))
        await model.syncNotes()
        let note = try #require(model.notes().first)

        model.editNote(note, text: "No photo")
        await writeToLand(of: model)
        await model.outbox.send()

        #expect(api.deleteFileAttempts.map(\.path) == ["\(folder)/a.jpeg"])
    }
}
