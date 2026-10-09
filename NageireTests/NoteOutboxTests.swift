import Foundation
import Testing
@testable import Nageire

@MainActor
struct NoteOutboxTests {
    private let store = InMemoryNoteStore()
    private let api = FakeAPI()

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_791_035_892)
        var suffixes = ["a1b2", "9f3c", "07de"]
    }

    private let clock = Clock()

    private func outbox(destination: Repository? = Repository(owner: "octocat", name: "notes")) -> NoteOutbox {
        let clock = clock
        let outbox = NoteOutbox(
            store: store,
            api: api,
            now: { clock.now },
            timeZone: { TimeZone(identifier: "Asia/Tokyo")! },
            suffix: { clock.suffixes.removeFirst() }
        )
        outbox.destination = destination
        return outbox
    }

    @Test func addingANoteStoresItOnTheDeviceBeforeAnythingIsSent() throws {
        let outbox = outbox()

        try outbox.add(body: "Hello")

        #expect(outbox.pendingCount == 1)
        #expect(store.outbox.map(\.fileName) == ["2026-10-03T135812Z-a1b2.md"])
        #expect(api.createFileAttempts.isEmpty)
    }

    @Test func sendingCommitsEachPendingNoteToItsMonthDirectoryOldestFirst() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        clock.now += 60
        try outbox.add(body: "Second")

        await outbox.send()

        #expect(api.createFileAttempts == [
            .init(
                path: "notes/2026/10/2026-10-03T135812Z-a1b2.md",
                repository: "octocat/notes",
                content: "---\ncreated: 2026-10-03T22:58:12+09:00\n---\n\nFirst\n",
                message: "Add 2026-10-03T135812Z-a1b2.md"
            ),
            .init(
                path: "notes/2026/10/2026-10-03T135912Z-9f3c.md",
                repository: "octocat/notes",
                content: "---\ncreated: 2026-10-03T22:59:12+09:00\n---\n\nSecond\n",
                message: "Add 2026-10-03T135912Z-9f3c.md"
            ),
        ])
        #expect(outbox.pendingCount == 0)
        #expect(store.files.count == 2)
    }

    @Test(arguments: [URLError(.notConnectedToInternet) as Error, GitHubAPIError.unexpectedStatus(503), GitHubAPIError.unexpectedStatus(409), SessionError.signedOut])
    func aFailureThatPassesOnItsOwnKeepsTheNotesForTheNextSendWithoutAWarning(failure: Error) async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        clock.now += 60
        try outbox.add(body: "Second")
        api.createFileResults = [.failure(failure)]

        await outbox.send()

        #expect(outbox.pendingCount == 2)
        #expect(api.createFileAttempts.count == 1)
        #expect(!outbox.wasRefused)

        await outbox.send()

        #expect(outbox.pendingCount == 0)
    }

    @Test(arguments: [404, 403, 422])
    func aRefusalByGitHubIsFlaggedUntilANoteGoesThrough(status: Int) async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        api.createFileResults = [.failure(GitHubAPIError.unexpectedStatus(status))]

        await outbox.send()

        #expect(outbox.wasRefused)
        #expect(outbox.pendingCount == 1)

        outbox.destination = Repository(owner: "octocat", name: "journal")
        await outbox.send()

        #expect(!outbox.wasRefused)
        #expect(outbox.pendingCount == 0)
        #expect(api.createFileAttempts.last?.repository == "octocat/journal")
    }

    @Test func changingTheDestinationClearsTheRefusalOfThePreviousOne() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        api.createFileResults = [.failure(GitHubAPIError.unexpectedStatus(404)), .failure(URLError(.timedOut))]
        await outbox.send()

        outbox.destination = Repository(owner: "octocat", name: "journal")
        await outbox.send()

        #expect(!outbox.wasRefused)
        #expect(outbox.pendingCount == 1)
    }

    @Test func aNameTakenByADifferentNoteIsSentUnderANewSuffix() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        api.createFileResults = [.failure(GitHubAPIError.fileAlreadyExists)]

        await outbox.send()

        #expect(api.createFileAttempts.map(\.path) == [
            "notes/2026/10/2026-10-03T135812Z-a1b2.md",
            "notes/2026/10/2026-10-03T135812Z-9f3c.md",
        ])
        #expect(api.createFileAttempts.last?.content == "---\ncreated: 2026-10-03T22:58:12+09:00\n---\n\nFirst\n")
        #expect(outbox.pendingCount == 0)
    }

    @Test func aNoteAddedDuringASendIsSentByThePassAlreadyRunning() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")

        async let sending: Void = outbox.send()
        while api.createFileAttempts.isEmpty {
            await Task.yield()
        }
        clock.now += 60
        try outbox.add(body: "Second")
        await outbox.send()
        await sending

        #expect(api.createFileAttempts.map(\.path) == [
            "notes/2026/10/2026-10-03T135812Z-a1b2.md",
            "notes/2026/10/2026-10-03T135912Z-9f3c.md",
        ])
        #expect(outbox.pendingCount == 0)
    }

    @Test func nothingIsSentWithoutADestination() async throws {
        let outbox = outbox(destination: nil)
        try outbox.add(body: "First")

        await outbox.send()

        #expect(api.createFileAttempts.isEmpty)
        #expect(outbox.pendingCount == 1)
    }

    @Test func notesLeftPendingByAnEarlierLaunchAreCountedAtStart() throws {
        try store.add(Note(fileName: "2026-10-03T135812Z-a1b2.md", contents: "left over\n"))

        #expect(outbox().pendingCount == 1)
    }
    private let sentPath = "notes/2026/10/2026-10-01T090000Z-07de.md"
    private var sentEntry: NoteEntry {
        NoteEntry(path: sentPath, contents: "---\ncreated: 2026-10-01T18:00:00+09:00\n---\n\nSent\n", isPending: false)
    }

    private func entry(of note: Note) -> NoteEntry {
        NoteEntry(path: note.repositoryPath, contents: note.contents, isPending: true)
    }

    @Test func editingANoteGitHubHoldsCommitsTheEditedFileOverIt() async throws {
        let outbox = outbox()

        try outbox.edit(sentEntry, text: "Edited")

        let contents = "---\ncreated: 2026-10-01T18:00:00+09:00\nupdated: 2026-10-03T22:58:12+09:00\n---\n\nEdited\n"
        #expect(outbox.changes == [.update(path: sentPath, contents: Data(contents.utf8))])
        #expect(api.writeFileAttempts.isEmpty)

        await outbox.send()

        #expect(api.writeFileAttempts == [
            .init(path: sentPath, repository: "octocat/notes", content: contents, message: "Update 2026-10-01T090000Z-07de.md"),
        ])
        #expect(outbox.pendingCount == 0)
    }

    @Test func editingANoteTwiceBeforeItIsSentMakesOneCommitWithTheLastText() async throws {
        let outbox = outbox()
        try outbox.edit(sentEntry, text: "Edited once")
        try outbox.edit(sentEntry, text: "Edited twice")

        await outbox.send()

        #expect(api.writeFileAttempts.count == 1)
        #expect(api.writeFileAttempts.first?.content.hasSuffix("\n\nEdited twice\n") == true)
    }

    @Test func deletingANoteGitHubHoldsRemovesItThereAndDropsAnEditStillWaiting() async throws {
        let outbox = outbox()
        try outbox.edit(sentEntry, text: "Edited")

        try outbox.delete(sentEntry)
        await outbox.send()

        #expect(api.writeFileAttempts.isEmpty)
        #expect(api.deleteFileAttempts == [
            .init(path: sentPath, repository: "octocat/notes", message: "Delete 2026-10-01T090000Z-07de.md"),
        ])
        #expect(outbox.pendingCount == 0)
    }

    @Test func anEditedNoteNotYetSentReachesGitHubInOneCommit() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        let note = outbox.pending[0]
        clock.now += 60

        try outbox.edit(entry(of: note), text: "First, edited")
        await outbox.send()

        #expect(api.createFileAttempts.isEmpty)
        #expect(api.writeFileAttempts.map(\.path) == [note.repositoryPath])
        #expect(api.writeFileAttempts.map(\.content) == ["---\ncreated: 2026-10-03T22:58:12+09:00\nupdated: 2026-10-03T22:59:12+09:00\n---\n\nFirst, edited\n"])
        #expect(outbox.pendingCount == 0)
    }

    @Test func aDeletedNoteNotYetSentIsNeverCommitted() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        let note = outbox.pending[0]

        try outbox.delete(entry(of: note))
        await outbox.send()

        #expect(api.createFileAttempts.isEmpty)
        #expect(api.writeFileAttempts.isEmpty)
        #expect(api.deleteFileAttempts.map(\.path) == [note.repositoryPath])
        #expect(outbox.pendingCount == 0)
    }

    @Test func anEditOfANoteWhoseCommitLandedUnnoticedGoesOverItInsteadOfAddingASecondFile() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        let note = outbox.pending[0]
        // The commit landed and only its response was lost.
        api.createFileResults = [.failure(URLError(.networkConnectionLost))]
        await outbox.send()
        api.remoteNotes = .success([note.repositoryPath: note.contents])

        try outbox.edit(entry(of: note), text: "First, edited")
        await outbox.send()

        #expect(api.createFileAttempts.count == 1)
        #expect(try api.remoteNotes.get().keys.sorted() == [note.repositoryPath])
        #expect(try api.remoteNotes.get()[note.repositoryPath]?.hasSuffix("\n\nFirst, edited\n") == true)
        #expect(outbox.pendingCount == 0)
    }

    @Test func aNoteEditedWhileItIsBeingSentIsSentAgainAsEdited() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        let note = outbox.pending[0]

        async let sending: Void = outbox.send()
        while api.createFileAttempts.isEmpty {
            await Task.yield()
        }
        try outbox.edit(entry(of: note), text: "First, edited")
        await sending

        #expect(api.createFileAttempts.map(\.content) == [note.contents])
        #expect(api.writeFileAttempts.first?.content.hasSuffix("\n\nFirst, edited\n") == true)
        #expect(store.files[note.repositoryPath] == api.writeFileAttempts.first.map { Data($0.content.utf8) })
        #expect(outbox.pendingCount == 0)
    }

    @Test func aNoteDeletedWhileItIsBeingSentIsDeletedOnGitHubToo() async throws {
        let outbox = outbox()
        try outbox.add(body: "First")
        let note = outbox.pending[0]

        async let sending: Void = outbox.send()
        while api.createFileAttempts.isEmpty {
            await Task.yield()
        }
        try outbox.delete(entry(of: note))
        await sending

        #expect(api.deleteFileAttempts.map(\.path) == [note.repositoryPath])
        #expect(store.files.isEmpty)
        #expect(outbox.pendingCount == 0)
    }

    @Test func aChangeGitHubDoesNotTakeWaitsForTheNextSend() async throws {
        let outbox = outbox()
        try outbox.edit(sentEntry, text: "Edited")
        api.changeResults = [.failure(URLError(.notConnectedToInternet)), .failure(GitHubAPIError.unexpectedStatus(403))]

        await outbox.send()

        #expect(outbox.pendingCount == 1)
        #expect(!outbox.wasRefused)

        await outbox.send()

        #expect(outbox.pendingCount == 1)
        #expect(outbox.wasRefused)

        await outbox.send()

        #expect(outbox.pendingCount == 0)
        #expect(!outbox.wasRefused)
    }

    @Test func savingANoteWithItsTextUnchangedIsNotAnEdit() throws {
        let outbox = outbox()

        try outbox.edit(sentEntry, text: "Sent\n\n")

        #expect(outbox.pendingCount == 0)
    }

    @Test func eachChangeGitHubTakesIsReported() async throws {
        let outbox = outbox()
        var reported: [NoteChange] = []
        outbox.onChanged = { reported.append($0) }
        try outbox.edit(sentEntry, text: "Edited")
        let update = try #require(outbox.changes.first)

        await outbox.send()

        #expect(reported == [update])
    }

    @Test func attachingAFileKeepsItInTheFolderBesideTheNoteAndReturnsItsLine() throws {
        let outbox = outbox()
        let entry = NoteEntry(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", contents: "a\n", isPending: false)

        let line = try outbox.attach(Data("jpeg".utf8), named: "IMG 0421.jpeg", to: entry)

        #expect(line == "![IMG_0421.jpeg](2026-10-03T135812Z-a1b2/IMG_0421.jpeg)")
        #expect(store.attachments == ["notes/2026/10/2026-10-03T135812Z-a1b2/IMG_0421.jpeg": Data("jpeg".utf8)])
    }

    @Test func aSecondFileOfTheSameNameGetsACounter() throws {
        let outbox = outbox()
        let entry = NoteEntry(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", contents: "a\n", isPending: false)
        _ = try outbox.attach(Data("first".utf8), named: "IMG.jpeg", to: entry)

        let line = try outbox.attach(Data("second".utf8), named: "IMG.jpeg", to: entry)

        #expect(line == "![IMG-2.jpeg](2026-10-03T135812Z-a1b2/IMG-2.jpeg)")
        #expect(store.attachments["notes/2026/10/2026-10-03T135812Z-a1b2/IMG-2.jpeg"] == Data("second".utf8))
    }
}
