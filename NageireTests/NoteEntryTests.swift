import Foundation
import Testing
@testable import Nageire

@MainActor
struct NoteEntryTests {
    private let path = "notes/2026/10/2026-10-03T135812Z-a1b2.md"

    @Test func theBodyIsTheTextAfterTheFrontMatterAndTheTimeComesFromCreated() {
        let entry = NoteEntry(path: path, contents: "---\ncreated: 2026-10-03T22:58:30+09:00\n---\n\nWent to the clinic.\nNext visit is next month.\n", isPending: false)

        #expect(entry.body == "Went to the clinic.\nNext visit is next month.")
        #expect(entry.createdAt == Date(timeIntervalSince1970: 1_791_035_910))
    }

    @Test func aNoteWrittenByThisAppReadsBackWithItsBodyAndTime() {
        let createdAt = Date(timeIntervalSince1970: 1_791_035_892)
        let note = Note(body: "Hello", createdAt: createdAt, timeZone: TimeZone(identifier: "Asia/Tokyo")!, suffix: "a1b2")

        let entry = NoteEntry(path: note.repositoryPath, contents: note.contents, isPending: true)

        #expect(entry.body == "Hello")
        #expect(entry.createdAt == createdAt)
        #expect(entry.isPending)
    }

    @Test func aFileWithoutFrontMatterIsAllBodyAndTakesItsTimeFromTheFileName() {
        let entry = NoteEntry(path: path, contents: "Just text\n", isPending: false)

        #expect(entry.body == "Just text")
        #expect(entry.createdAt == Date(timeIntervalSince1970: 1_791_035_892))
    }

    @Test func aFileWithNeitherFrontMatterNorATimestampedNameHasNoTime() {
        let entry = NoteEntry(path: "notes/ideas.md", contents: "Just text\n", isPending: false)

        #expect(entry.body == "Just text")
        #expect(entry.createdAt == nil)
    }

    @Test func otherFrontMatterFieldsAreLeftOutOfTheBody() {
        let entry = NoteEntry(path: path, contents: "---\ntitle: Clinic\ncreated: 2026-10-03T22:58:30+09:00\n---\nBody\n", isPending: false)

        #expect(entry.body == "Body")
        #expect(entry.createdAt == Date(timeIntervalSince1970: 1_791_035_910))
    }

    @Test func emptyFrontMatterIsRemoved() {
        #expect(NoteEntry(path: path, contents: "---\n---\nBody\n", isPending: false).body == "Body")
    }

    @Test func aHorizontalRuleInTheTextIsNotTakenForFrontMatter() {
        let entry = NoteEntry(path: path, contents: "Above\n\n---\n\nBelow\n", isPending: false)

        #expect(entry.body == "Above\n\n---\n\nBelow")
    }

    @Test func anUnclosedFrontMatterLeavesTheWholeFileAsBody() {
        #expect(NoteEntry(path: path, contents: "---\ncreated: x\nBody\n", isPending: false).body == "---\ncreated: x\nBody")
    }
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let editedAt = Date(timeIntervalSince1970: 1_791_035_892)

    @Test func editingReplacesTheTextKeepsTheFrontMatterAndAddsTheTimeOfTheEdit() {
        let entry = NoteEntry(path: path, contents: "---\ntitle: Clinic\ncreated: 2026-10-01T18:00:00+09:00\n---\n\nBefore\n", isPending: false)

        let edited = entry.contents(withText: "\n  After\n\n", updatedAt: editedAt, timeZone: tokyo)

        #expect(edited == "---\ntitle: Clinic\ncreated: 2026-10-01T18:00:00+09:00\nupdated: 2026-10-03T22:58:12+09:00\n---\n\n  After\n")
    }

    @Test func editingAgainReplacesTheTimeOfTheEarlierEdit() {
        let entry = NoteEntry(path: path, contents: "---\ncreated: 2026-10-01T18:00:00+09:00\nupdated: 2026-10-02T08:00:00+09:00\n---\n\nBefore\n", isPending: false)

        let edited = entry.contents(withText: "After", updatedAt: editedAt, timeZone: tokyo)

        #expect(edited == "---\ncreated: 2026-10-01T18:00:00+09:00\nupdated: 2026-10-03T22:58:12+09:00\n---\n\nAfter\n")
    }

    @Test func editingAFileWithoutFrontMatterDoesNotGiveItOne() {
        let entry = NoteEntry(path: path, contents: "Just text\n", isPending: false)

        #expect(entry.contents(withText: "Other text", updatedAt: editedAt, timeZone: tokyo) == "Other text\n")
    }

    @Test func editingAFileWithEmptyFrontMatterPutsTheTimeOfTheEditInIt() {
        let entry = NoteEntry(path: path, contents: "---\n---\nBody\n", isPending: false)

        #expect(entry.contents(withText: "Body, edited", updatedAt: editedAt, timeZone: tokyo) == "---\nupdated: 2026-10-03T22:58:12+09:00\n---\n\nBody, edited\n")
    }

    @Test func theTimeOfTheLastEditComesFromUpdated() {
        let entry = NoteEntry(path: path, contents: "---\ncreated: 2026-10-01T18:00:00+09:00\nupdated: 2026-10-03T22:58:12+09:00\n---\n\nBody\n", isPending: false)

        #expect(entry.updatedAt == editedAt)
        #expect(NoteEntry(path: path, contents: "Body\n", isPending: false).updatedAt == nil)
    }

    @Test func theTextToEditKeepsTheIndentationOfItsFirstLine() {
        let entry = NoteEntry(path: path, contents: "---\ncreated: 2026-10-01T18:00:00+09:00\n---\n\n    let x = 1\nDone\n", isPending: false)

        #expect(entry.editableText == "    let x = 1\nDone")
    }
}
