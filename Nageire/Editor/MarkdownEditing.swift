import Foundation

/// What the accessory bar and the Format menu ask of the editor.
enum EditorCommand: Equatable {
    case heading
    case list
    case checklist
    case bold
    case italic
    case link
}

/// A replacement in the text and where the selection goes after it, in UTF-16 units as the text views count.
struct TextEdit: Equatable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

/// The edits the editor makes beyond typing: a command's marks at the selection, and the next marker on Return.
/// They are computed from the text alone, and the views apply them through their own paths, which undo knows.
enum MarkdownEditing {
    /// The edit a command makes at the selection, or nil when there is nothing to do.
    static func edit(for command: EditorCommand, in text: String, selection: NSRange) -> TextEdit? {
        let text = text as NSString
        switch command {
        case .heading:
            // The heading button adds a title, which is the first line of the note, wherever the caret is.
            if case .heading = MarkdownLine(text.substring(with: line(at: 0, in: text))).kind { return nil }
            return TextEdit(range: NSRange(location: 0, length: 0), replacement: "# ", selection: NSRange(location: selection.location + 2, length: selection.length))
        case .list, .checklist:
            return marked(command, in: text, selection: selection)
        case .bold:
            return wrapped(selection, in: text, mark: "**")
        case .italic:
            return wrapped(selection, in: text, mark: "*")
        case .link:
            // With a name selected the caret goes to the address; with none, to the name.
            let name = text.substring(with: selection)
            let caret = name.isEmpty ? selection.location + 1 : selection.location + name.utf16.count + 3
            return TextEdit(range: selection, replacement: "[\(name)]()", selection: NSRange(location: caret, length: 0))
        }
    }

    /// What Return does with the caret in a list: the next marker on a new line, or on an empty item the end of the
    /// list, which takes the marker away. Nil where Return is a line break: outside a list, inside the marker, or over a selection.
    static func returnEdit(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let text = text as NSString
        let range = line(at: selection.location, in: text)
        let string = text.substring(with: range)
        let markdown = MarkdownLine(string)
        switch markdown.kind {
        case .item, .task:
            break
        default:
            return nil
        }
        let prefix = NSRange(markdown.prefix, in: string)
        guard selection.location - range.location >= prefix.upperBound else { return nil }
        if prefix.upperBound == range.length {
            return TextEdit(range: NSRange(location: range.location, length: prefix.length), replacement: "", selection: NSRange(location: range.location, length: 0))
        }
        // The next item of a task list is open, and of a numbered list one higher.
        var marker = string[markdown.prefix]
        if let box = markdown.box {
            marker.replaceSubrange(box, with: "[ ]")
        }
        marker = marker.replacing(Self.number) { String((Int($0.output) ?? 0) + 1) }
        let replacement = "\n" + marker
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + replacement.utf16.count, length: 0))
    }

    /// The selection between two marks, and still selected; with nothing selected, the caret between them.
    private static func wrapped(_ selection: NSRange, in text: NSString, mark: String) -> TextEdit {
        TextEdit(range: selection, replacement: mark + text.substring(with: selection) + mark, selection: NSRange(location: selection.location + mark.utf16.count, length: selection.length))
    }

    /// The list or checklist marker on the caret's line, or nil where it has one or is no place for one:
    /// a heading, a quote, an image, or for a box a numbered item, which the editor does not draw a box in.
    private static func marked(_ command: EditorCommand, in text: NSString, selection: NSRange) -> TextEdit? {
        let range = line(at: selection.location, in: text)
        let string = text.substring(with: range)
        let markdown = MarkdownLine(string)
        let at: Int
        let marker: String
        switch (command, markdown.kind) {
        case (.checklist, .item) where string[markdown.indentation.upperBound] == "-":
            at = range.location + NSRange(markdown.prefix, in: string).upperBound
            marker = "[ ] "
        case (.list, .text), (.list, .blank), (.checklist, .text), (.checklist, .blank):
            at = range.location + NSRange(markdown.indentation, in: string).upperBound
            marker = command == .checklist ? "- [ ] " : "- "
        default:
            return nil
        }
        let moved = at <= selection.location ? NSRange(location: selection.location + marker.utf16.count, length: selection.length) : selection
        return TextEdit(range: NSRange(location: at, length: 0), replacement: marker, selection: moved)
    }

    private static let number = /\d+/

    /// The line around a location, without its line break.
    private static func line(at location: Int, in text: NSString) -> NSRange {
        var start = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }
}
