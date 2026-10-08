import Foundation

/// One line of a note, read as Markdown: what kind of block it opens and where its marker ends.
struct MarkdownLine: Equatable {
    enum Kind: Equatable {
        case text
        case blank
        /// `level` counts the `#` marks, 1 to 6.
        case heading(level: Int)
        /// A bullet or a numbered item.
        case item
        case task(done: Bool)
        case quote
        /// A line that is one image and nothing else. `file` is the last part of `path`.
        case image(file: String, path: String)
    }

    let kind: Kind
    /// The indentation, the marker, and the space after it. Empty for text, a blank line, and an image.
    let prefix: Range<String.Index>
    /// The `[ ]` or `[x]` of a task.
    let box: Range<String.Index>?

    init(_ line: some StringProtocol) {
        let line = Substring(line)
        let none = line.startIndex..<line.startIndex
        if let image = line.trimmingCharacters(in: .whitespaces).wholeMatch(of: Self.imageLine) {
            let path = String(image.output.1)
            self.init(kind: .image(file: path.split(separator: "/").last.map(String.init) ?? path, path: path), prefix: none, box: nil)
        } else if let marker = line.prefixMatch(of: Self.blockMarker) {
            let (_, heading, box, done, quote) = marker.output
            let kind: Kind = if let heading {
                .heading(level: heading.count)
            } else if let done {
                .task(done: done != " ")
            } else if quote != nil {
                .quote
            } else {
                .item
            }
            self.init(kind: kind, prefix: marker.range, box: box.map { $0.startIndex..<$0.endIndex })
        } else {
            self.init(kind: line.allSatisfy(\.isWhitespace) ? .blank : .text, prefix: none, box: nil)
        }
    }

    private init(kind: Kind, prefix: Range<String.Index>, box: Range<String.Index>?) {
        self.kind = kind
        self.prefix = prefix
        self.box = box
    }

    /// The marker that opens a heading, a list item with or without its task box, a numbered item, or a quote.
    private static let blockMarker = /^[ \t]*(?:(#{1,6}) |[-*+] (?:(\[([ xX])\]) )?|\d+[.)] |(>) )/
    private static let imageLine = /!\[[^\]]*\]\(([^)]+)\)/
}
