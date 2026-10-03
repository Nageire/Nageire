import Foundation
import Testing
@testable import Nageire

@MainActor
struct FileNoteStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "FileNoteStoreTests-\(UUID().uuidString)")
    private var store: FileNoteStore { FileNoteStore(directory: directory) }
    private let older = Note(fileName: "2026-10-03T135812Z-a1b2.md", contents: "older\n")
    private let newer = Note(fileName: "2026-10-03T140210Z-9f3c.md", contents: "newer\n")

    @Test func nothingIsPendingBeforeANoteIsAdded() throws {
        #expect(try store.pendingCount() == 0)
        #expect(try store.firstPending() == nil)
    }

    @Test func theOldestAddedNoteIsFirstAndSurvivesANewStoreOnTheSameDirectory() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(newer)
        try store.add(older)

        let reopened = FileNoteStore(directory: directory)

        #expect(try reopened.pendingCount() == 2)
        #expect(try reopened.firstPending() == older)
    }

    @Test func aSentNoteLeavesThePendingOnesAndStaysOnTheDevice() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(older)
        try store.add(newer)

        try store.markSent(older)

        #expect(try store.pendingCount() == 1)
        #expect(try store.firstPending() == newer)
        let kept = try String(contentsOf: directory.appending(path: "sent/\(older.fileName)"), encoding: .utf8)
        #expect(kept == "older\n")
    }

    @Test func replacingAPendingNoteKeepsOnlyTheReplacement() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.add(older)
        let renamed = older.renamed(suffix: "ffff")

        try store.replacePending(older, with: renamed)

        #expect(try store.pendingCount() == 1)
        #expect(try store.firstPending() == Note(fileName: "2026-10-03T135812Z-ffff.md", contents: "older\n"))
    }
}
