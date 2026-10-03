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
}
