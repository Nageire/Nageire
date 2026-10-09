import Foundation
import Testing
@testable import Nageire

@MainActor
struct FileNoteStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "FileNoteStoreTests-\(UUID().uuidString)")
    private var store: FileNoteStore { FileNoteStore(directory: directory) }
    private let older = Note(fileName: "2026-10-03T135812Z-a1b2.md", contents: "older\n")
    private let newer = Note(fileName: "2026-10-03T140210Z-9f3c.md", contents: "newer\n")

    @Test func nothingIsStoredBeforeANoteIsAdded() throws {
        #expect(try store.pending().isEmpty)
        #expect(try store.library().isEmpty)
    }

    @Test func addedNotesArePendingOldestFirstAndSurviveANewStoreOnTheSameDirectory() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(newer)
        try store.add(older)

        let reopened = FileNoteStore(directory: directory)

        #expect(try reopened.pending() == [older, newer])
    }

    @Test func aSentNoteMovesFromThePendingOnesIntoTheLibraryAtItsRepositoryPath() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(older)
        try store.add(newer)

        try store.markSent(older)

        #expect(try store.pending() == [newer])
        #expect(try store.library() == [StoredFile(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", contents: Data("older\n".utf8))])
    }

    @Test func replacingAPendingNoteKeepsOnlyTheReplacement() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(older)

        try store.replacePending(older, with: older.renamed(suffix: "ffff"))

        #expect(try store.pending() == [Note(fileName: "2026-10-03T135812Z-ffff.md", contents: "older\n")])
    }

    @Test func libraryFilesAreSavedReplacedAndRemovedByPath() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = "notes/2026/11/2026-11-01T090000Z-07de.md"
        try store.saveToLibrary(StoredFile(path: path, contents: Data("first\n".utf8)))
        try store.saveToLibrary(StoredFile(path: path, contents: Data("second\n".utf8)))

        #expect(try store.library() == [StoredFile(path: path, contents: Data("second\n".utf8))])

        try store.removeFromLibrary(path: path)

        #expect(try store.library().isEmpty)
    }

    @Test func removingTheLibraryLeavesThePendingNotes() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(older)
        try store.saveToLibrary(StoredFile(path: "notes/2026/11/a.md", contents: Data("a\n".utf8)))

        try store.removeLibrary()
        try store.removeLibrary()

        #expect(try store.library().isEmpty)
        #expect(try store.pending() == [older])
    }
    @Test func aRemovedPendingNoteIsNoLongerPending() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(older)
        try store.add(newer)

        try store.removePending(older)

        #expect(try store.pending() == [newer])
    }

    @Test func recordedChangesSurviveANewStoreAndTheLibraryBeingRemoved() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let update = NoteChange.update(path: "notes/2026/10/a.md", contents: Data("edited\n".utf8))
        let deletion = NoteChange.delete(path: "notes/2026/11/b.md")
        try store.record(update)
        try store.record(deletion)
        try store.removeLibrary()

        #expect(try FileNoteStore(directory: directory).changes() == [update, deletion])
    }

    @Test func aChangeTakesThePlaceOfTheOneWaitingForTheSamePath() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = "notes/2026/10/a.md"
        try store.record(.update(path: path, contents: Data("first\n".utf8)))
        try store.record(.update(path: path, contents: Data("second\n".utf8)))

        #expect(try store.changes() == [.update(path: path, contents: Data("second\n".utf8))])

        try store.record(.delete(path: path))

        #expect(try store.changes() == [.delete(path: path)])
    }

    @Test func resolvingAChangeBringsTheLibraryUpToIt() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = "notes/2026/10/a.md"
        let dropped = "notes/2026/11/b.md"
        try store.saveToLibrary(StoredFile(path: kept, contents: Data("before\n".utf8)))
        try store.saveToLibrary(StoredFile(path: dropped, contents: Data("before\n".utf8)))
        try store.record(.update(path: kept, contents: Data("edited\n".utf8)))
        try store.record(.delete(path: dropped))

        try store.resolve(.update(path: kept, contents: Data("edited\n".utf8)))
        try store.resolve(.delete(path: dropped))

        #expect(try store.library() == [StoredFile(path: kept, contents: Data("edited\n".utf8))])
        #expect(try store.changes().isEmpty)
    }

    @Test func resolvingAChangeRemovesItUnlessAnotherOneHasTakenItsPlace() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = "notes/2026/10/a.md"
        let first = NoteChange.update(path: path, contents: Data("first\n".utf8))
        let second = NoteChange.update(path: path, contents: Data("second\n".utf8))
        try store.record(first)
        try store.record(second)

        try store.resolve(first)

        #expect(try store.changes() == [second])

        try store.resolve(second)

        #expect(try store.changes().isEmpty)
    }

    @Test func aWaitingFileAndALibraryFileAreReadBackByPathAndListedByFolder() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = "notes/2026/10/2026-10-03T135812Z-a1b2"
        try store.addAttachment(StoredFile(path: "\(folder)/waiting.jpg", contents: Data("w".utf8)))
        try FileManager.default.createDirectory(at: directory.appending(path: "library/\(folder)"), withIntermediateDirectories: true)
        try Data("s".utf8).write(to: directory.appending(path: "library/\(folder)/sent.jpg"))

        #expect(try store.attachmentNames(inFolder: folder).sorted() == ["sent.jpg", "waiting.jpg"])
        #expect(try store.attachment(at: "\(folder)/waiting.jpg") == Data("w".utf8))
        #expect(try store.attachment(at: "\(folder)/sent.jpg") == Data("s".utf8))
        #expect(try store.attachment(at: "\(folder)/missing.jpg") == nil)
        #expect(try store.library().isEmpty)
    }
}
