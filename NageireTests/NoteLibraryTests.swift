import Foundation
import Testing
@testable import Nageire

@MainActor
struct NoteLibraryTests {
    private let store = InMemoryNoteStore()
    private let api = FakeAPI()
    private let repository = Repository(owner: "octocat", name: "notes")
    private let october = "notes/2026/10/2026-10-03T135812Z-a1b2.md"
    private let november = "notes/2026/11/2026-11-01T090000Z-07de.md"

    private func library() -> NoteLibrary {
        NoteLibrary(store: store, api: api)
    }

    @Test func refreshingFetchesTheNotesOfTheRepositoryNewestFirst() async {
        api.remoteNotes = .success([october: "October\n", november: "November\n"])
        let library = library()

        await library.refresh(from: repository)

        #expect(library.notes().map(\.body) == ["November", "October"])
        #expect(library.notes().allSatisfy { !$0.isPending })
        #expect(!library.lastRefreshFailed)
    }

    @Test func aSecondRefreshFetchesOnlyWhatChanged() async {
        api.remoteNotes = .success([october: "October\n", november: "November\n"])
        let library = library()
        await library.refresh(from: repository)
        api.remoteNotes = .success([october: "October, edited on GitHub\n", november: "November\n"])

        await library.refresh(from: repository)

        #expect(api.fetchedBlobs.count == 3)
        #expect(library.notes().map(\.body) == ["November", "October, edited on GitHub"])
    }

    @Test func aNoteDeletedFromTheRepositoryLeavesTheList() async {
        api.remoteNotes = .success([october: "October\n", november: "November\n"])
        let library = library()
        await library.refresh(from: repository)
        api.remoteNotes = .success([november: "November\n"])

        await library.refresh(from: repository)

        #expect(library.notes().map(\.body) == ["November"])
    }

    @Test func aFailedRefreshKeepsTheNotesAlreadyOnTheDeviceAndIsFlaggedUntilOneSucceeds() async {
        api.remoteNotes = .success([october: "October\n"])
        let library = library()
        await library.refresh(from: repository)
        api.remoteNotes = .failure(URLError(.notConnectedToInternet))

        await library.refresh(from: repository)

        #expect(library.notes().map(\.body) == ["October"])
        #expect(library.lastRefreshFailed)

        api.remoteNotes = .success([october: "October\n"])
        await library.refresh(from: repository)

        #expect(!library.lastRefreshFailed)
    }

    @Test func notesAlreadyOnTheDeviceAreListedBeforeAnyRefresh() throws {
        try store.saveToLibrary(StoredFile(path: october, contents: Data("October\n".utf8)))

        #expect(library().notes().map(\.body) == ["October"])
    }

    @Test func pendingNotesAreListedAmongTheOthersAndMarked() async throws {
        api.remoteNotes = .success([october: "October\n"])
        let library = library()
        await library.refresh(from: repository)
        let pending = [Note(fileName: "2026-10-20T080000Z-9f3c.md", contents: "Unsent\n")]

        #expect(library.notes(including: pending).map(\.body) == ["Unsent", "October"])
        #expect(library.notes(including: pending).map(\.isPending) == [true, false])
    }

    @Test func aNoteSentFromThisDeviceIsNotFetchedAgain() async throws {
        let note = Note(fileName: "2026-10-03T135812Z-a1b2.md", contents: "October\n")
        try store.add(note)
        try store.markSent(note)
        api.remoteNotes = .success([october: "October\n"])
        let library = library()

        await library.refresh(from: repository)

        #expect(api.fetchedBlobs.isEmpty)
        #expect(library.notes().map(\.body) == ["October"])
    }

    @Test func searchMatchesTheBodyIgnoringCaseAndAnEmptyQueryMatchesEverything() async {
        api.remoteNotes = .success([october: "Went to the Clinic\n", november: "Walked in the park\n"])
        let library = library()
        await library.refresh(from: repository)

        #expect(library.notes().matching("clinic").map(\.body) == ["Went to the Clinic"])
        #expect(library.notes().matching("  ").count == 2)
        #expect(library.notes().matching("dentist").isEmpty)
    }

    @Test func aNoteThisDeviceSentIsListedWithoutARefresh() {
        let library = library()

        library.add(Note(fileName: "2026-10-03T135812Z-a1b2.md", contents: "October\n"))

        #expect(library.notes().map(\.path) == [october])
        #expect(library.notes().map(\.isPending) == [false])
    }

    @Test func aFileWithATimeInItsFrontMatterIsOrderedByThatTimeWhateverItsName() async {
        api.remoteNotes = .success([
            october: "October\n",
            "notes/ideas.md": "---\ncreated: 2026-12-01T10:00:00+09:00\n---\nDecember, added by hand\n",
            "notes/undated.md": "No time at all\n",
        ])
        let library = library()

        await library.refresh(from: repository)

        #expect(library.notes().map(\.body) == ["December, added by hand", "October", "No time at all"])
    }

    @Test func aRefreshOvertakenByEmptyingTheLibraryWritesNothing() async {
        api.remoteNotes = .success([october: "October\n"])
        let library = library()

        let refresh = Task { await library.refresh(from: repository) }
        while api.listedRepositories.isEmpty {
            await Task.yield()
        }
        library.removeAll()
        await refresh.value

        #expect(library.notes().isEmpty)
        #expect(store.files.isEmpty)
    }

    @Test func aRefreshRequestedDuringAnotherRunsAfterItForTheRepositoryItNamed() async {
        api.remoteNotes = .success([october: "October\n"])
        let library = library()

        let first = Task { await library.refresh(from: repository) }
        while api.listedRepositories.isEmpty {
            await Task.yield()
        }
        await library.refresh(from: Repository(owner: "octocat", name: "journal"))
        await first.value

        #expect(api.listedRepositories == ["octocat/notes", "octocat/journal"])
    }

    @Test func aNoteSentWhileARefreshIsFetchingStaysInTheList() async throws {
        api.remoteNotes = .success([october: "October\n"])
        let library = library()
        let note = Note(fileName: "2026-11-01T090000Z-07de.md", contents: "November\n")

        let refresh = Task { await library.refresh(from: repository) }
        while api.fetchedBlobs.isEmpty {
            await Task.yield()
        }
        try store.add(note)
        try store.markSent(note)
        library.add(note)
        await refresh.value

        #expect(library.notes().map(\.body) == ["November", "October"])
    }

    @Test func aPendingNoteTheRepositoryAlreadyHoldsIsListedOnceAsUnsent() async {
        api.remoteNotes = .success([october: "October\n"])
        let library = library()
        await library.refresh(from: repository)

        let notes = library.notes(including: [Note(fileName: "2026-10-03T135812Z-a1b2.md", contents: "October\n")])

        #expect(notes.map(\.path) == [october])
        #expect(notes.map(\.isPending) == [true])
    }

    @Test func theBlobIdentifierMatchesTheOneGitComputes() {
        // `printf 'hello\n' | git hash-object --stdin`
        #expect(RemoteFile.sha(of: Data("hello\n".utf8)) == "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    @Test func anEditStillToBeSentIsListedInPlaceOfTheCopyAndMarked() async {
        api.remoteNotes = .success([october: "October\n", november: "November\n"])
        let library = library()
        await library.refresh(from: repository)
        let changes = [NoteChange.update(path: october, contents: Data("Edited here\n".utf8))]

        #expect(library.notes(unsent: changes).map(\.body) == ["November", "Edited here"])
        #expect(library.notes(unsent: changes).map(\.isPending) == [false, true])

        await library.refresh(from: repository)

        #expect(library.notes(unsent: changes).map(\.body) == ["November", "Edited here"])
    }

    @Test func aDeletionStillToBeSentKeepsTheNoteOutOfTheListThroughARefresh() async {
        api.remoteNotes = .success([october: "October\n", november: "November\n"])
        let library = library()
        await library.refresh(from: repository)
        let changes = [NoteChange.delete(path: october)]

        await library.refresh(from: repository)

        #expect(library.notes(unsent: changes).map(\.body) == ["November"])
    }

    @Test func anEditOfANoteTheCopyDoesNotHoldIsListedAllTheSame() {
        let changes = [NoteChange.update(path: october, contents: Data("Edited before signing out\n".utf8))]

        #expect(library().notes(unsent: changes).map(\.body) == ["Edited before signing out"])
    }

    @Test func aChangeGitHubHasTakenIsListedWithoutARefresh() async {
        api.remoteNotes = .success([october: "October\n", november: "November\n"])
        let library = library()
        await library.refresh(from: repository)

        library.apply(.update(path: october, contents: Data("Edited\n".utf8)))
        library.apply(.delete(path: november))

        #expect(library.notes().map(\.body) == ["Edited"])
        #expect(api.listedRepositories.count == 1)
    }

    @Test func aChangeTakenDuringARefreshIsFollowedByAnotherRefresh() async throws {
        api.remoteNotes = .success([october: "October\n"])
        let library = library()
        await library.refresh(from: repository)

        async let refreshing: Void = library.refresh(from: repository)
        while api.listedRepositories.count < 2 {
            await Task.yield()
        }
        let change = NoteChange.update(path: october, contents: Data("Edited\n".utf8))
        try store.resolve(change)
        api.remoteNotes = .success([october: "Edited\n"])
        library.apply(change)
        await refreshing

        #expect(api.listedRepositories.count == 3)
        #expect(library.notes().map(\.body) == ["Edited"])
    }
}
