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
}
