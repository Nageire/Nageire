#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The fonts of a note's text at the current text size: the body and what the Markdown turns it into.
struct EditorFonts {
    let body: PlatformFont
    let bold: PlatformFont
    let italic: PlatformFont
    let code: PlatformFont
    let caption: PlatformFont
    /// By heading level, the first three; a deeper heading takes the third.
    let headings: [PlatformFont]

    #if canImport(UIKit)
    init(serif: Bool, traits: UITraitCollection) {
        let plain = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body, compatibleWith: traits)
        let design: UIFontDescriptor.SystemDesign = serif ? .serif : .default
        let base = plain.withDesign(design) ?? plain
        body = UIFont(descriptor: base, size: 0)
        bold = UIFont(descriptor: base.withSymbolicTraits(.traitBold) ?? base, size: 0)
        italic = UIFont(descriptor: base.withSymbolicTraits(.traitItalic) ?? base, size: 0)
        let metrics = UIFontMetrics(forTextStyle: .body)
        code = UIFont(descriptor: plain.withDesign(.monospaced) ?? plain, size: metrics.scaledValue(for: 15, compatibleWith: traits))
        caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        headings = NoteHeading.allCases.map { heading in
            let descriptor = UIFont.systemFont(ofSize: metrics.scaledValue(for: heading.size, compatibleWith: traits), weight: .semibold).fontDescriptor
            return UIFont(descriptor: descriptor.withDesign(design) ?? descriptor, size: 0)
        }
    }
    #else
    init(serif: Bool) {
        let plain = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
        let design: NSFontDescriptor.SystemDesign = serif ? .serif : .default
        let base = plain.withDesign(design) ?? plain
        let fallback = NSFont.preferredFont(forTextStyle: .body)
        body = NSFont(descriptor: base, size: 0) ?? fallback
        bold = NSFont(descriptor: base.withSymbolicTraits(.bold), size: 0) ?? fallback
        italic = NSFont(descriptor: base.withSymbolicTraits(.italic), size: 0) ?? fallback
        // The design's mono is 15 beside a body of 17; the Mac's body is smaller and the mono keeps the ratio.
        code = NSFont.monospacedSystemFont(ofSize: fallback.pointSize * 15 / 17, weight: .regular)
        caption = NSFont.preferredFont(forTextStyle: .caption1)
        headings = NoteHeading.allCases.map { heading in
            let descriptor = NSFont.systemFont(ofSize: heading.size, weight: .semibold).fontDescriptor
            return NSFont(descriptor: descriptor.withDesign(design) ?? descriptor, size: 0) ?? fallback
        }
    }
    #endif

    func heading(level: Int) -> PlatformFont {
        headings[min(level, headings.count) - 1]
    }
}

/// What the editor draws over a line beyond its text: the box of a task, the thumbnail of an image.
enum LineDecoration: Hashable {
    /// `box` is where the `[ ]` is in the paragraph.
    case checkbox(done: Bool, box: NSRange)
    case thumbnail(file: String)
}

extension NSAttributedString.Key {
    static let lineDecoration = NSAttributedString.Key("nageire.lineDecoration")
}

/// Styles one paragraph of a note. The string stays as it is in the file; the attributes say what its Markdown means.
struct MarkdownStyler {
    let fonts: EditorFonts
    /// The attributes of text that no mark touches, which are also the typing attributes.
    let base: [NSAttributedString.Key: Any]
    private let marks: [NSAttributedString.Key: Any] = [.foregroundColor: PlatformColor.textMark]
    private let blankStyle: NSParagraphStyle
    /// The widths the design fixes, measured once: the space in the body font, and the space after each heading's marks.
    private let spaceWidth: CGFloat
    private let headingSpaceWidths: [CGFloat]

    init(fonts: EditorFonts) {
        self.fonts = fonts
        base = [.font: fonts.body, .foregroundColor: PlatformColor.ink, .paragraphStyle: Self.paragraphStyle(leading: Leading.body)]
        let blank = Self.paragraphStyle(leading: Leading.body)
        blank.minimumLineHeight = fonts.body.platformLineHeight * Leading.body * EditorMetrics.blankLineFactor
        blank.maximumLineHeight = blank.minimumLineHeight
        blankStyle = blank
        spaceWidth = Self.width(of: " ", in: fonts.body)
        headingSpaceWidths = fonts.headings.map { Self.width(of: " ", in: $0) }
    }

    /// - Parameter isFirst: The paragraph opens the note, so a heading there has no space above.
    func styled(_ string: String, isFirst: Bool) -> NSAttributedString {
        // A paragraph ends in its line break, which a file from elsewhere may write as CRLF: one character to Swift.
        let text = string.last?.isNewline == true ? string.dropLast() : Substring(string)
        let line = MarkdownLine(text)
        let styled = NSMutableAttributedString(string: string, attributes: base)
        let whole = NSRange(location: 0, length: styled.length)
        let prefix = NSRange(line.prefix, in: string)
        switch line.kind {
        case .text:
            break
        case .blank:
            styled.addAttribute(.paragraphStyle, value: blankStyle, range: whole)
        case let .heading(level):
            let style = Self.paragraphStyle(leading: Leading.heading)
            style.paragraphSpacingBefore = isFirst ? 0 : EditorMetrics.headingSpaceAbove
            style.paragraphSpacing = EditorMetrics.headingSpaceBelow
            styled.addAttributes([.font: fonts.heading(level: level), .paragraphStyle: style], range: whole)
            styled.addAttributes(marks, range: prefix)
            // The gap between the marks and the text is the design's, whatever the space measures.
            let spaceWidth = headingSpaceWidths[min(level, headingSpaceWidths.count) - 1]
            styled.addAttribute(.kern, value: EditorMetrics.markerGap - spaceWidth, range: NSRange(location: prefix.upperBound - 1, length: 1))
        case .item, .quote, .task:
            // The indentation, the marker, and the space after it, then for a task the box and one more space.
            let markerEnd = line.box?.lowerBound ?? line.prefix.upperBound
            let indentation = text[line.prefix].prefix { $0.isWhitespace }
            let marker = String(text[indentation.endIndex..<markerEnd].dropLast())
            let markerWidth = Self.width(of: marker, in: fonts.body)
            // A one-character marker sits in the design's column; a number is wider than the column and keeps the gap alone.
            let column = marker.count == 1 ? EditorMetrics.markerColumn : markerWidth
            let style = Self.paragraphStyle(leading: Leading.body)
            style.headIndent = (indentation.isEmpty ? 0 : Self.width(of: String(indentation), in: fonts.body)) + column + EditorMetrics.markerGap
            styled.addAttributes(marks, range: prefix)
            styled.addAttribute(.kern, value: column + EditorMetrics.markerGap - markerWidth - spaceWidth, range: NSRange(location: NSRange(indentation.endIndex..<markerEnd, in: string).upperBound - 1, length: 1))
            if case let .task(done) = line.kind, let boxRange = line.box {
                let box = NSRange(boxRange, in: string)
                // The brackets stay in the file; on screen the box is drawn in their place, and the kern on the last one makes them as wide as it.
                styled.addAttribute(.foregroundColor, value: PlatformColor.clear, range: box)
                styled.addAttribute(.kern, value: EditorMetrics.checkbox - Self.width(of: String(text[boxRange]), in: fonts.body), range: NSRange(location: box.upperBound - 1, length: 1))
                styled.addAttribute(.kern, value: EditorMetrics.markerGap - spaceWidth, range: NSRange(location: box.upperBound, length: 1))
                style.headIndent += EditorMetrics.checkbox + EditorMetrics.markerGap
                styled.addAttribute(.lineDecoration, value: LineDecoration.checkbox(done: done, box: box), range: whole)
                if done {
                    let rest = NSRange(location: prefix.upperBound, length: whole.length - prefix.upperBound)
                    styled.addAttributes([.foregroundColor: PlatformColor.ink2, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: rest)
                }
            }
            styled.addAttribute(.paragraphStyle, value: style, range: whole)
        case let .image(file, _):
            // The raw line stays in sight, in the color of a mark, with the thumbnail under it.
            styled.addAttributes(marks, range: whole)
            styled.addAttribute(.lineDecoration, value: LineDecoration.thumbnail(file: file), range: whole)
        }
        for span in line.spans {
            let range = NSRange(span.range, in: string)
            switch span.role {
            case .mark, .linkAddress:
                styled.addAttributes(marks, range: range)
            case .bold:
                styled.addAttribute(.font, value: fonts.bold, range: range)
            case .italic:
                styled.addAttribute(.font, value: fonts.italic, range: range)
            case .code:
                styled.addAttribute(.font, value: fonts.code, range: range)
            case .linkText:
                styled.addAttributes([
                    .foregroundColor: PlatformColor.accentText,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: PlatformColor.accentText,
                ], range: range)
            }
        }
        return styled
    }

    private static func paragraphStyle(leading: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = leading
        style.paragraphSpacing = EditorMetrics.lineGap
        return style
    }

    private static func width(of text: String, in font: PlatformFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }
}

nonisolated extension PlatformFont {
    /// The height of one line, which AppKit's font does not name.
    var platformLineHeight: CGFloat { ascender - descender + leading }
}
