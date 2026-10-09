import Foundation

/// The measures of the editor's lines, from the editor bullet of `docs/design-reference.md`.
nonisolated enum EditorMetrics {
    /// Between the lines of a note.
    static let lineGap: CGFloat = 2
    /// A line with nothing on it, as a fraction of a line of text.
    static let blankLineFactor: CGFloat = 0.55
    /// Above a heading that does not open the note, and below every heading.
    static let headingSpaceAbove: CGFloat = 10
    static let headingSpaceBelow: CGFloat = 4
    /// The column that holds a list marker, and the gap after it or after a heading's marks.
    static let markerColumn: CGFloat = 12
    static let markerGap: CGFloat = 10
    /// The box of a task and the stroke of an open one.
    static let checkbox: CGFloat = 22
    static let checkboxBorder: CGFloat = 1.5
    /// Around the box, where a tap still counts as the box's.
    static let checkboxHitMargin: CGFloat = 8
    static let thumbnail = CGSize(width: 164, height: 123)
    /// Above the thumbnail and between it and its caption, and after the caption.
    static let thumbnailGap: CGFloat = 6
    static let thumbnailSpaceAfter: CGFloat = 8
}
