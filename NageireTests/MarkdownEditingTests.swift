import Foundation
import Testing
@testable import Nageire

@MainActor
struct MarkdownEditingTests {
    /// The text after the command and the selection in it, or nil when the command does nothing.
    private func applying(_ command: EditorCommand, to text: String, at location: Int, length: Int = 0) -> (text: String, selection: NSRange)? {
        applied(MarkdownEditing.edit(for: command, in: text, selection: NSRange(location: location, length: length)), to: text)
    }

    /// The text after Return and the selection in it, or nil when Return is a line break.
    private func returning(in text: String, at location: Int, length: Int = 0) -> (text: String, selection: NSRange)? {
        applied(MarkdownEditing.returnEdit(in: text, selection: NSRange(location: location, length: length)), to: text)
    }

    private func applied(_ edit: TextEdit?, to text: String) -> (text: String, selection: NSRange)? {
        guard let edit else { return nil }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    @Test func theHeadingButtonPutsAMarkerOnTheFirstLineAndKeepsTheCaretWhereItWas() {
        let result = applying(.heading, to: "買い出し\n- 剣山", at: 7)

        #expect(result?.text == "# 買い出し\n- 剣山")
        #expect(result?.selection == NSRange(location: 9, length: 0))
    }

    @Test func theHeadingButtonDoesNothingOnANoteThatHasATitle() {
        #expect(applying(.heading, to: "# 買い出し", at: 3) == nil)
    }

    @Test func theListButtonMarksTheLineOfTheCaret() {
        let result = applying(.list, to: "a\nb\nc", at: 2)

        #expect(result?.text == "a\n- b\nc")
        #expect(result?.selection == NSRange(location: 4, length: 0))
    }

    @Test func theListButtonKeepsTheIndentationAndLeavesAnItemAsItIs() {
        #expect(applying(.list, to: "  a", at: 3)?.text == "  - a")
        #expect(applying(.list, to: "- a", at: 1) == nil)
    }

    @Test func theChecklistButtonAddsABoxToAnItemAndAMarkerWithABoxToText() {
        #expect(applying(.checklist, to: "- a", at: 3)?.text == "- [ ] a")
        #expect(applying(.checklist, to: "a", at: 1)?.text == "- [ ] a")
        #expect(applying(.checklist, to: "- [x] a", at: 1) == nil)
    }

    @Test func theMarkersAreNotPutOnAHeadingAQuoteAnImageOrANumberedItem() {
        #expect(applying(.list, to: "# a", at: 3) == nil)
        #expect(applying(.list, to: "> a", at: 3) == nil)
        #expect(applying(.checklist, to: "![a](a.jpg)", at: 0) == nil)
        #expect(applying(.checklist, to: "1. a", at: 4) == nil)
    }

    @Test func boldWrapsTheSelectionAndKeepsItSelected() {
        let result = applying(.bold, to: "枝を二本だけ", at: 0, length: 4)

        #expect(result?.text == "**枝を二本**だけ")
        #expect(result?.selection == NSRange(location: 2, length: 4))
    }

    @Test func boldWithNothingSelectedPutsTheCaretBetweenTheMarks() {
        let result = applying(.bold, to: "a", at: 1)

        #expect(result?.text == "a****")
        #expect(result?.selection == NSRange(location: 3, length: 0))
    }

    @Test func italicWrapsInSingleMarks() {
        #expect(applying(.italic, to: "ab", at: 0, length: 2)?.text == "*ab*")
    }

    @Test func aLinkFromASelectionPutsTheCaretInTheAddress() {
        let result = applying(.link, to: "予定", at: 0, length: 2)

        #expect(result?.text == "[予定]()")
        #expect(result?.selection == NSRange(location: 5, length: 0))
    }

    @Test func aLinkFromNothingPutsTheCaretInTheName() {
        let result = applying(.link, to: "", at: 0)

        #expect(result?.text == "[]()")
        #expect(result?.selection == NSRange(location: 1, length: 0))
    }

    @Test func returnInAnItemOpensTheNextItem() {
        let result = returning(in: "- 枝", at: 3)

        #expect(result?.text == "- 枝\n- ")
        #expect(result?.selection == NSRange(location: 6, length: 0))
    }

    @Test func returnInATaskOpensAnOpenTaskWithTheIndentation() {
        #expect(returning(in: "  - [x] 洗う", at: 10)?.text == "  - [x] 洗う\n  - [ ] ")
    }

    @Test func returnInANumberedItemCountsOn() {
        #expect(returning(in: "9. a", at: 4)?.text == "9. a\n10. ")
    }

    @Test func returnInTheMiddleOfAnItemSplitsIt() {
        #expect(returning(in: "- ab", at: 3)?.text == "- a\n- b")
    }

    @Test func returnOnAnEmptyItemTakesTheMarkerAway() {
        let result = returning(in: "- a\n- [ ] \nb", at: 10)

        #expect(result?.text == "- a\n\nb")
        #expect(result?.selection == NSRange(location: 4, length: 0))
    }

    @Test func returnIsALineBreakOutsideAListInsideTheMarkerAndOverASelection() {
        #expect(returning(in: "a", at: 1) == nil)
        #expect(returning(in: "- a", at: 1) == nil)
        #expect(returning(in: "- a", at: 2, length: 1) == nil)
    }
}
