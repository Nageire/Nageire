import SwiftUI

/// The roles the stylesheet in `docs/design/tokens.css` gives its colors. The colors themselves
/// (`.paper`, `.ink2`, `.accentText`) are the color sets of the asset catalog, which Xcode turns
/// into names of the same kind; the accent is `.tint`.
extension ShapeStyle where Self == Color {
    static var surfaceCard: Color { .paperRaised }
    /// The stream's canvas: the paper, and in the sidebar on macOS the sunken paper.
    #if os(macOS)
    static var surfaceStream: Color { .paperSunken }
    #else
    static var surfaceStream: Color { .paper }
    #endif
    static var textSecondary: Color { .ink2 }
    /// What the on-device model proposed and the person has not made their own.
    static var textDerived: Color { .ink2 }
    /// The Markdown marks left visible in the editor.
    static var textMark: Color { .inkFaint }
}

enum Spacing {
    /// The distance from the edge of the screen to its content.
    #if os(macOS)
    static let gutter: CGFloat = 24
    #else
    static let gutter: CGFloat = 20
    #endif
    /// The distance from the edge of a list to its rows: the gutter on iPhone, and less in the sidebar on macOS.
    #if os(macOS)
    static let listGutter: CGFloat = 16
    #else
    static let listGutter = gutter
    #endif
    /// Above and below the content of a list row.
    static let rowPadding: CGFloat = 12
    /// Between the lines of a list row.
    static let rowGap: CGFloat = 4
    /// The height of a button or a field, and the least a tap target measures.
    static let control: CGFloat = 44
    static let controlCompact: CGFloat = 34
}

enum Radius {
    static let input: CGFloat = 10
    static let thumbnail: CGFloat = 10
    static let card: CGFloat = 14
    static let sheet: CGFloat = 20
}

extension EdgeInsets {
    /// The insets of a row of the stream: the row padding above and below, the list gutter at the sides.
    static let stream = EdgeInsets(top: Spacing.rowPadding, leading: Spacing.listGutter, bottom: Spacing.rowPadding, trailing: Spacing.listGutter)
    /// The insets of a day's heading in the stream, which carries its own space above and below.
    static let streamHeader = EdgeInsets(top: 0, leading: Spacing.listGutter, bottom: 0, trailing: Spacing.listGutter)
}
