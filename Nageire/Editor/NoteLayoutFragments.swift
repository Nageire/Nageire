import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The colors of what the fragments draw, resolved where the layout is asked for: a fragment is
/// drawn off the main actor's isolation and cannot reach the color sets itself.
struct DecorationPalette: Sendable {
    let accent: PlatformColor
    let onAccent: PlatformColor = .onAccent
    let ink2: PlatformColor = .ink2
    let paperSunken: PlatformColor = .paperSunken
    let hairline: PlatformColor = .hairline
}

/// A task's line with its box drawn where the `[ ]` is. The brackets are in the text, clear and as wide as the box.
nonisolated final class CheckboxLayoutFragment: NSTextLayoutFragment {
    let done: Bool
    /// Where the `[ ]` is in the paragraph.
    let box: NSRange
    /// The text's, which the box is centered on.
    private let capHeight: CGFloat
    private let palette: DecorationPalette

    init(textElement: NSTextElement, done: Bool, box: NSRange, capHeight: CGFloat, palette: DecorationPalette) {
        self.done = done
        self.box = box
        self.capHeight = capHeight
        self.palette = palette
        super.init(textElement: textElement, range: textElement.elementRange)
    }

    required init?(coder: NSCoder) {
        fatalError("A layout fragment is made by the layout manager, never decoded.")
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(boxRect)
    }

    /// The square over the brackets, centered on the capitals of the first line, in the fragment's coordinates.
    /// The line's own middle is higher: the leading above the glyphs is the line's, not theirs.
    var boxRect: CGRect {
        guard let line = textLineFragments.first else { return .zero }
        let x = line.typographicBounds.minX + line.locationForCharacter(at: box.location).x
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        let side = EditorMetrics.checkbox
        return CGRect(x: x, y: baseline - capHeight / 2 - side / 2, width: side, height: side)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        let rect = boxRect.offsetBy(dx: point.x, dy: point.y)
        guard !rect.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if done {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: Radius.checkbox, cornerHeight: Radius.checkbox, transform: nil))
            context.setFillColor(palette.accent.cgColor)
            context.fillPath()
            // The check of the design, at 15, as two strokes.
            context.setStrokeColor(palette.onAccent.cgColor)
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: rect.minX + 6, y: rect.minY + 11.5))
            context.addLine(to: CGPoint(x: rect.minX + 9.5, y: rect.minY + 15))
            context.addLine(to: CGPoint(x: rect.minX + 16, y: rect.minY + 8))
            context.strokePath()
        } else {
            let border = EditorMetrics.checkboxBorder
            context.addPath(CGPath(roundedRect: rect.insetBy(dx: border / 2, dy: border / 2), cornerWidth: Radius.checkbox, cornerHeight: Radius.checkbox, transform: nil))
            context.setStrokeColor(palette.ink2.cgColor)
            context.setLineWidth(border)
            context.strokePath()
        }
    }
}

/// An image's line with its thumbnail under it, and the file's name as a caption.
/// The file is not on the device yet, so the thumbnail is its frame alone until the attachments arrive.
nonisolated final class ThumbnailLayoutFragment: NSTextLayoutFragment {
    private let caption: CTLine
    private let captionWidth: CGFloat
    private let captionAscent: CGFloat
    private let captionHeight: CGFloat
    private let palette: DecorationPalette
    /// One device pixel, the thickness of the frame.
    private let hairline: CGFloat

    init(textElement: NSTextElement, file: String, font: PlatformFont, palette: DecorationPalette, hairline: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        caption = CTLineCreateWithAttributedString(NSAttributedString(string: file, attributes: attributes))
        var ascent: CGFloat = 0
        captionWidth = CTLineGetTypographicBounds(caption, &ascent, nil, nil)
        captionAscent = ascent
        captionHeight = font.platformLineHeight
        self.palette = palette
        self.hairline = hairline
        super.init(textElement: textElement, range: textElement.elementRange)
    }

    required init?(coder: NSCoder) {
        fatalError("A layout fragment is made by the layout manager, never decoded.")
    }

    override var bottomMargin: CGFloat {
        EditorMetrics.thumbnailGap + EditorMetrics.thumbnail.height + EditorMetrics.thumbnailGap + captionHeight + EditorMetrics.thumbnailSpaceAfter
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(thumbnailRect).union(captionRect)
    }

    private var thumbnailRect: CGRect {
        let textBottom = textLineFragments.last?.typographicBounds.maxY ?? 0
        return CGRect(origin: CGPoint(x: 0, y: textBottom + EditorMetrics.thumbnailGap), size: EditorMetrics.thumbnail)
    }

    private var captionRect: CGRect {
        CGRect(x: 0, y: thumbnailRect.maxY + EditorMetrics.thumbnailGap, width: captionWidth, height: captionHeight)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        context.saveGState()
        defer { context.restoreGState() }
        let frame = thumbnailRect.offsetBy(dx: point.x, dy: point.y)
        context.addPath(CGPath(roundedRect: frame, cornerWidth: Radius.thumbnail, cornerHeight: Radius.thumbnail, transform: nil))
        context.setFillColor(palette.paperSunken.cgColor)
        context.fillPath()
        context.addPath(CGPath(roundedRect: frame.insetBy(dx: hairline / 2, dy: hairline / 2), cornerWidth: Radius.thumbnail, cornerHeight: Radius.thumbnail, transform: nil))
        context.setStrokeColor(palette.hairline.cgColor)
        context.setLineWidth(hairline)
        context.strokePath()
        // The context's origin is at the top, so the text matrix turns the glyphs the right way up.
        let captionOrigin = captionRect.offsetBy(dx: point.x, dy: point.y).origin
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: captionOrigin.x, y: captionOrigin.y + captionAscent)
        context.setFillColor(palette.ink2.cgColor)
        CTLineDraw(caption, context)
    }
}
