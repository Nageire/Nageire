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

@MainActor
struct NoteEntryTitleTests {
    private func entry(_ body: String) -> NoteEntry {
        NoteEntry(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", contents: body, isPending: false)
    }

    @Test func aHeadingOnTheFirstLineIsTheTitleAndTheExcerptStartsUnderIt() {
        let entry = entry("# 稽古の記録\n\n今日は**枝を二本**だけ。\n\n- 枝は水際で決まる\n- [x] 剣山を洗う\n")

        #expect(entry.displayTitle == "稽古の記録")
        #expect(entry.hasHeading)
        #expect(entry.excerpt == "今日は枝を二本だけ。\n枝は水際で決まる\n剣山を洗う")
    }

    @Test func aPlainFirstLineIsCutAtItsFirstSentenceAndTheRestOpensTheExcerpt() {
        let entry = entry("来週の火曜は稽古と重なる。木曜の午後に電話する。\n\n- [ ] 受付に電話\n")

        #expect(entry.displayTitle == "来週の火曜は稽古と重なる。")
        #expect(!entry.hasHeading)
        #expect(entry.excerpt == "木曜の午後に電話する。\n受付に電話")
    }

    @Test func aFirstLineWithoutASentenceEndIsCutAtFortyCharacters() {
        let line = String(repeating: "あ", count: 50)
        let entry = entry(line)

        #expect(entry.displayTitle == String(repeating: "あ", count: 40))
        #expect(entry.excerpt == String(repeating: "あ", count: 10))
    }

    @Test func aFirstLineThatIsATaskOrInBoldIsTitledByItsWords() {
        #expect(entry("- [ ] 受付に電話\n- [ ] カレンダーを直す\n").displayTitle == "受付に電話")
        #expect(entry("**大事**な話。あとで。\n").displayTitle == "大事な話。")
    }

    @Test func aMarkWithoutItsPairStaysInTheTitle() {
        #expect(entry("2 * 3 と IMG_0412_a.jpeg\n").displayTitle == "2 * 3 と IMG_0412_a.jpeg")
    }

    @Test func anEnglishSentenceEndsAtAPeriodBeforeASpaceButNotInsideANumber() {
        #expect(entry("Call the dentist. Fix the calendar after.\n").displayTitle == "Call the dentist.")
        #expect(entry("Version 2.5 ships. Then rest.\n").displayTitle == "Version 2.5 ships.")
    }

    @Test func aNoteThatIsOneImageIsCalledByTheFileName() {
        let entry = entry("![IMG_0421.jpeg](2026-10-01T111500Z-0a06/IMG_0421.jpeg)\n")

        #expect(entry.displayTitle == "IMG_0421.jpeg")
        #expect(entry.attachmentCount == 1)
        #expect(entry.excerpt == "")
    }

    @Test func aShortFirstLineIsTheWholeTitleAndLeavesNoExcerpt() {
        let entry = entry("雨の前のあの灰色に近い。")

        #expect(entry.displayTitle == "雨の前のあの灰色に近い。")
        #expect(entry.excerpt == "")
    }

    @Test func imageLinesCountAsAttachmentsAndLeaveTheExcerptWhileLinksKeepTheirText() {
        let entry = entry("# 見積もり\n\n![IMG_0412.jpeg](2026-10-01T111500Z-0a06/IMG_0412.jpeg)\n\n![](https://example.com/a.png)\n\n次は[教室の予定](https://example.com)を見る。\n")

        #expect(entry.attachmentCount == 1)
        #expect(entry.excerpt == "次は教室の予定を見る。")
    }
}
