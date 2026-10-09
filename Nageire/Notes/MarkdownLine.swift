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

    enum Role: Equatable {
        /// A character of the syntax: `**`, a backtick, the brackets of a link.
        case mark
        case bold
        case italic
        case code
        case linkText
        case linkAddress
    }

    /// A run of the text after the prefix with what it is.
    struct Span: Equatable {
        let range: Range<String.Index>
        let role: Role
    }

    let kind: Kind
    /// The indentation, the marker, and the space after it. Empty for text, a blank line, and an image.
    let prefix: Range<String.Index>
    /// The `[ ]` or `[x]` of a task.
    let box: Range<String.Index>?
    /// The emphasis, the code, and the links after the prefix, with their marks, in order. None on an image line.
    let spans: [Span]

    init(_ line: some StringProtocol) {
        let line = Substring(line)
        let none = line.startIndex..<line.startIndex
        if line.contains("!["), let image = line.trimmingCharacters(in: .whitespaces).wholeMatch(of: Self.imageLine) {
            let path = String(image.output.1)
            self.init(kind: .image(file: String(path[fileNameStart(of: path)...]), path: path), prefix: none, box: nil)
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
            self.init(kind: kind, prefix: marker.range, box: box.map { $0.startIndex..<$0.endIndex }, spans: Self.spans(in: line[marker.range.upperBound...]))
        } else {
            self.init(kind: line.allSatisfy(\.isWhitespace) ? .blank : .text, prefix: none, box: nil, spans: Self.spans(in: line))
        }
    }

    private init(kind: Kind, prefix: Range<String.Index>, box: Range<String.Index>?, spans: [Span] = []) {
        self.kind = kind
        self.prefix = prefix
        self.box = box
        self.spans = spans
    }

    /// Code is read first, so that a mark inside it is text, then links, bold, and italic, each
    /// skipping what an earlier one took. A mark never pairs across a line.
    private static func spans(in text: Substring) -> [Span] {
        var taken: [Range<String.Index>] = []
        var spans: [Span] = []
        func span(_ part: Substring, _ role: Role) -> Span {
            Span(range: part.startIndex..<part.endIndex, role: role)
        }
        /// The run between its two marks.
        func enclosed(_ match: Range<String.Index>, _ inner: Substring, _ role: Role) -> [Span] {
            [
                Span(range: match.lowerBound..<inner.startIndex, role: .mark),
                span(inner, role),
                Span(range: inner.endIndex..<match.upperBound, role: .mark),
            ]
        }
        /// Each match of the regex that does not overlap what was taken. A rejected match is left
        /// behind one character at a time, so that a mark inside it can still open a later run.
        func each<Output>(_ regex: Regex<Output>, where isWanted: (Regex<Output>.Match) -> Bool = { _ in true }, _ body: (Regex<Output>.Match) -> [Span]) {
            var start = text.startIndex
            while start < text.endIndex, let match = text[start...].firstMatch(of: regex) {
                if !taken.contains(where: { $0.overlaps(match.range) }), isWanted(match) {
                    taken.append(match.range)
                    spans += body(match)
                    start = match.range.upperBound
                } else {
                    start = text.index(after: match.range.lowerBound)
                }
            }
        }
        each(code) { enclosed($0.range, $0.output.1, .code) }
        each(link) { match in
            let (_, name, address) = match.output
            return [
                Span(range: match.range.lowerBound..<name.startIndex, role: .mark),
                span(name, .linkText),
                Span(range: name.endIndex..<address.startIndex, role: .mark),
                span(address, .linkAddress),
                Span(range: address.endIndex..<match.range.upperBound, role: .mark),
            ]
        }
        for (regex, role) in [(bold, Role.bold), (italic, .italic)] {
            // An underscore inside a word, as in a file name, is not a mark.
            each(regex, where: { $0.output.2 == nil || !isInsideAWord($0.range, in: text) }) { match in
                guard let inner = match.output.1 ?? match.output.2 else { return [] }
                return enclosed(match.range, inner, role)
            }
        }
        return spans.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func isInsideAWord(_ range: Range<String.Index>, in text: Substring) -> Bool {
        let before = text[..<range.lowerBound].last
        let after = text[range.upperBound...].first
        return before?.isLetter == true || before?.isNumber == true || after?.isLetter == true || after?.isNumber == true
    }

    /// The marker that opens a heading, a list item with or without its task box, a numbered item, or a quote.
    private static let blockMarker = /^[ \t]*(?:(#{1,6}) |[-*+] (?:(\[([ xX])\]) )?|\d+[.)] |(>) )/
    private static let imageLine = /!\[[^\]]*\]\(([^)]+)\)/
    private static let code = /`([^`]+)`/
    private static let link = /\[([^\]]+)\]\(([^)]*)\)/
    private static let bold = /\*\*([^*]+)\*\*|__([^_]+)__/
    private static let italic = /\*([^*]+)\*|_([^_]+)_/
}
