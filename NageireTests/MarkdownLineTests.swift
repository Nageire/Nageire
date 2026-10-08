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
}
