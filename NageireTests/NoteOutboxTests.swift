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
}
