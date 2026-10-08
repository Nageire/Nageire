import Foundation
import Testing
@testable import Nageire

@MainActor
struct MarkdownLineTests {
    @Test(arguments: [
        ("# 稽古の記録", MarkdownLine.Kind.heading(level: 1), "# "),
        ("### 三つ目", .heading(level: 3), "### "),
        ("- 枝は水際で決まる", .item, "- "),
        ("* 花は低く", .item, "* "),
        ("3. 柚子", .item, "3. "),
        ("- [ ] 剣山（小）", .task(done: false), "- [ ] "),
        ("- [x] 剣山を洗う", .task(done: true), "- [x] "),
        ("> 器は空いているところに意味がある", .quote, "> "),
        ("今日は枝を二本だけ。", .text, ""),
        ("", .blank, ""),
        ("   ", .blank, ""),
    ])
    func theMarkerOpensTheBlockAndIsThePrefix(line: String, kind: MarkdownLine.Kind, prefix: String) {
        let markdown = MarkdownLine(line)

        #expect(markdown.kind == kind)
        #expect(line[markdown.prefix] == prefix)
    }

    @Test func anIndentedItemKeepsItsIndentationInThePrefix() {
        let line = "  - 入れ子"
        let markdown = MarkdownLine(line)

        #expect(markdown.kind == .item)
        #expect(line[markdown.prefix] == "  - ")
    }

    @Test func theBoxOfATaskIsItsBrackets() {
        let line = "- [ ] 受付に電話"

        #expect(line[MarkdownLine(line).box!] == "[ ]")
        #expect(MarkdownLine("- 受付に電話").box == nil)
    }

    @Test func aMarkerWithoutItsSpaceIsText() {
        #expect(MarkdownLine("#tag").kind == .text)
        #expect(MarkdownLine("-1").kind == .text)
        #expect(MarkdownLine("- [ ]").kind == .item)
    }

    @Test func aLineThatIsOneImageNamesTheFileByTheLastPartOfItsPath() {
        let markdown = MarkdownLine("![枝](2026-10-03T001200Z-0a05/kuwa.jpg)")

        #expect(markdown.kind == .image(file: "kuwa.jpg", path: "2026-10-03T001200Z-0a05/kuwa.jpg"))
        #expect(markdown.prefix.isEmpty)
    }

    @Test func anImageWithTextAroundItIsNotAnImageLine() {
        #expect(MarkdownLine("見て ![枝](kuwa.jpg)").kind == .text)
        #expect(MarkdownLine("![枝](kuwa.jpg) を見て").kind == .text)
    }

    /// Each span as its text and its role, readable in a failure.
    private func spans(of line: String) -> [String] {
        MarkdownLine(line).spans.map { "\(line[$0.range]) \($0.role)" }
    }

    @Test func theMarksOfEmphasisAndCodeAreSetApartFromWhatTheyEnclose() {
        #expect(spans(of: "今日は**枝を二本**だけ。*余白*と`code`") == [
            "** mark", "枝を二本 bold", "** mark",
            "* mark", "余白 italic", "* mark",
            "` mark", "code code", "` mark",
        ])
    }

    @Test func aLinkIsItsNameAndItsAddressBetweenMarks() {
        #expect(spans(of: "次は[教室の予定](https://example.com/s)を見る") == [
            "[ mark", "教室の予定 linkText", "]( mark", "https://example.com/s linkAddress", ") mark",
        ])
    }

    @Test func aMarkInsideCodeIsText() {
        #expect(spans(of: "`a * b` と *c*") == ["` mark", "a * b code", "` mark", "* mark", "c italic", "* mark"])
    }

    @Test func anUnderscoreInsideAWordIsNotAMark() {
        #expect(MarkdownLine("IMG_0412_a.jpeg を送る").spans.isEmpty)
        #expect(MarkdownLine("_強調_ する").spans.map(\.role) == [.mark, .italic, .mark])
    }

    @Test func theSpansOfAnItemStartAfterItsMarker() {
        let line = "- *余白を恐れない*"

        #expect(MarkdownLine(line).spans.map { String(line[$0.range]) } == ["*", "余白を恐れない", "*"])
    }

    @Test func anUnpairedMarkIsText() {
        #expect(MarkdownLine("2 * 3 = 6").spans.isEmpty)
        #expect(MarkdownLine("**開いたまま").spans.isEmpty)
    }
}
