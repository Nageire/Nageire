import Foundation
import Testing
@testable import Nageire
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
struct MarkdownStylerTests {
    #if canImport(UIKit)
    private let styler = MarkdownStyler(fonts: EditorFonts(serif: false, traits: UITraitCollection(preferredContentSizeCategory: .large)))
    #else
    private let styler = MarkdownStyler(fonts: EditorFonts(serif: false))
    #endif

    private func styled(_ text: String, isFirst: Bool = false) -> NSAttributedString {
        styler.styled(text, isFirst: isFirst)
    }

    private func paragraphStyle(of text: String, isFirst: Bool = false) -> NSParagraphStyle? {
        styled(text, isFirst: isFirst).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    private func font(in styled: NSAttributedString, at index: Int) -> PlatformFont? {
        styled.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont
    }

    private func color(in styled: NSAttributedString, at index: Int) -> PlatformColor? {
        styled.attribute(.foregroundColor, at: index, effectiveRange: nil) as? PlatformColor
    }

    @Test func theStringStaysAsItWas() {
        let text = "- [x] **done** `a` [l](u)\n"

        #expect(styled(text).string == text)
    }

    @Test func aHeadingTakesItsSizeAndItsMarkIsFaint() {
        let styled = styled("## 見出し\n")

        #expect(color(in: styled, at: 0) == .textMark)
        #expect(font(in: styled, at: 3)?.pointSize == NoteHeading.second.size)
        #expect(color(in: styled, at: 3) == .ink)
    }

    @Test func theFirstHeadingHasNoSpaceAboveAndALaterOneHas() {
        #expect(paragraphStyle(of: "# 見出し\n", isFirst: true)?.paragraphSpacingBefore == 0)
        #expect(paragraphStyle(of: "# 見出し\n")?.paragraphSpacingBefore == EditorMetrics.headingSpaceAbove)
    }

    @Test func aDoneTaskIsStruckThroughInTheSecondInkAndItsBracketsAreClear() {
        let styled = styled("- [x] 剣山を洗う\n")

        #expect(color(in: styled, at: 2) == .clear)
        #expect(color(in: styled, at: 6) == .ink2)
        #expect(styled.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(styled.attribute(.lineDecoration, at: 0, effectiveRange: nil) as? LineDecoration == .checkbox(done: true, box: NSRange(location: 2, length: 3)))
    }

    @Test func anOpenTaskKeepsItsTextInInk() {
        let styled = styled("- [ ] 受付に電話\n")

        #expect(color(in: styled, at: 6) == .ink)
        #expect(styled.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) == nil)
    }

    @Test func theTextOfAnItemWrapsUnderItself() {
        let column = EditorMetrics.markerColumn + EditorMetrics.markerGap

        #expect(paragraphStyle(of: "- 枝は水際で決まる\n")?.headIndent == column)
        #expect(paragraphStyle(of: "- [ ] 枝は水際で決まる\n")?.headIndent == column + EditorMetrics.checkbox + EditorMetrics.markerGap)
    }

    @Test func emphasisChangesTheFontAndLeavesItsMarksFaint() {
        let styled = styled("今日は**枝**と*花*と`器`\n")

        #expect(color(in: styled, at: 3) == .textMark)
        #expect(font(in: styled, at: 5) == styler.fonts.bold)
        #expect(font(in: styled, at: 10) == styler.fonts.italic)
        #expect(font(in: styled, at: 14) == styler.fonts.code)
        #expect(font(in: styled, at: 0) == styler.fonts.body)
    }

    @Test func aLinkIsItsNameInTheAccentWithTheAddressFaint() {
        let styled = styled("[予定](https://example.com)\n")

        #expect(color(in: styled, at: 0) == .textMark)
        #expect(color(in: styled, at: 1) == .accentText)
        #expect(styled.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(color(in: styled, at: 6) == .textMark)
    }

    @Test func anImageLineIsFaintAndCarriesItsThumbnail() {
        let styled = styled("![枝](2026-10-03T001200Z-0a05/kuwa.jpg)\n")

        #expect(color(in: styled, at: 0) == .textMark)
        #expect(styled.attribute(.lineDecoration, at: 0, effectiveRange: nil) as? LineDecoration == .thumbnail(file: "kuwa.jpg"))
    }

    @Test func anImageLineThatEndsInCRLFCarriesItsThumbnailToo() {
        let styled = styled("![枝](kuwa.jpg)\r\n")

        #expect(styled.attribute(.lineDecoration, at: 0, effectiveRange: nil) as? LineDecoration == .thumbnail(file: "kuwa.jpg"))
    }

    @Test func aBlankLineIsLowerThanALineOfText() {
        let blank = paragraphStyle(of: "\n")?.maximumLineHeight ?? 0

        #expect(blank > 0)
        #expect(blank < styler.fonts.body.platformLineHeight * Leading.body)
    }
}
