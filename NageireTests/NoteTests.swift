import Foundation
import Testing
@testable import Nageire

@MainActor
struct NoteTests {
    // 2026-10-03 13:58:12 UTC, which is 22:58:12 in Tokyo.
    private let createdAt = Date(timeIntervalSince1970: 1_791_035_892)
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    @Test func theFileNameIsTheUTCTimeOfWritingFollowedByTheSuffix() {
        let note = Note(body: "Hello", createdAt: createdAt, timeZone: tokyo, suffix: "a1b2")

        #expect(note.fileName == "2026-10-03T135812Z-a1b2.md")
    }

    @Test func theContentsStartWithTheLocalTimeOfWritingAsFrontMatter() {
        let note = Note(body: "Went to the clinic.\nNext visit is next month.", createdAt: createdAt, timeZone: tokyo, suffix: "a1b2")

        #expect(note.contents == """
            ---
            created: 2026-10-03T22:58:12+09:00
            ---

            Went to the clinic.
            Next visit is next month.

            """)
    }

    @Test func blankLinesAroundTheBodyAndTrailingSpacesAreRemovedButTheFirstLineKeepsItsIndentation() {
        let note = Note(body: "\n  \n    let x = 1  \n\nnext\n\n", createdAt: createdAt, timeZone: tokyo, suffix: "a1b2")

        #expect(note.contents.hasSuffix("---\n\n    let x = 1  \n\nnext\n"))
    }

    @Test func theRepositoryPathPutsTheNoteUnderTheYearAndMonthOfItsUTCTime() {
        // 2026-10-31 15:30:00 UTC is already November 1st in Tokyo; the directory follows the name, not the local date.
        let note = Note(body: "Hello", createdAt: Date(timeIntervalSince1970: 1_793_460_600), timeZone: tokyo, suffix: "07de")

        #expect(note.repositoryPath == "notes/2026/10/2026-10-31T153000Z-07de.md")
    }

    @Test func aRandomSuffixIsFourLowercaseHexDigits() {
        let suffix = Note.randomSuffix()

        #expect(suffix.count == 4)
        #expect(suffix.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test func renamingKeepsTheTimestampAndContentsAndChangesOnlyTheSuffix() {
        let note = Note(body: "Hello", createdAt: createdAt, timeZone: tokyo, suffix: "a1b2")

        #expect(note.renamed(suffix: "ffff") == Note(fileName: "2026-10-03T135812Z-ffff.md", contents: note.contents))
    }
}
