import Foundation

/// A note as the list shows it: the text without its front matter, and when it was written.
struct NoteEntry: Identifiable, Hashable {
    let path: String
    /// The whole file, front matter included.
    let contents: String
    let body: String
    let createdAt: Date?
    let updatedAt: Date?
    /// GitHub does not have the note as it is shown: it is new, or edited, and still waiting to be sent.
    let isPending: Bool

    var id: String { path }

    init(path: String, contents: String, isPending: Bool) {
        self.path = path
        self.contents = contents
        self.isPending = isPending
        let (frontMatter, text) = Self.split(contents)
        body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A file that reached the repository some other way may have no front matter.
        // The app's own file names still carry the time; any other file is listed without one.
        createdAt = Self.date(of: "created", in: frontMatter) ?? Note.timeOfWriting(inFileName: path[fileNameStart(of: path)...])
        updatedAt = Self.date(of: "updated", in: frontMatter)
    }

    static let dateFormat = Date.FormatStyle.dateTime.year().month().day().hour().minute()

    /// Orders by the time shown in the list. Files without a time come last, and the file name settles ties.
    static func isNewer(_ a: NoteEntry, _ b: NoteEntry) -> Bool {
        switch (a.createdAt, b.createdAt) {
        case let (a?, b?) where a != b: a > b
        case (_?, nil): true
        case (nil, _?): false
        default: a.path[fileNameStart(of: a.path)...] > b.path[fileNameStart(of: b.path)...]
        }
    }

    /// The text as the editor starts with it. Unlike `body` it keeps the indentation of the first line,
    /// which saving the edit would otherwise remove from the file.
    var editableText: String {
        Note.trimmed(Self.split(contents).body)
    }

    /// The file with its text replaced. The front matter stays as it is apart from `updated`.
    func contents(withText text: String, updatedAt: Date, timeZone: TimeZone) -> String {
        let text = Note.trimmed(text)
        // A file without front matter was not written by the app, and the app's format is not imposed on it.
        guard let frontMatter = Self.split(contents).frontMatter else { return "\(text)\n" }
        let updated = "updated: \(updatedAt.formatted(Note.createdStyle(in: timeZone)))"
        var fields = frontMatter.isEmpty ? [] : frontMatter.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let index = fields.firstIndex(where: { $0.hasPrefix("updated:") }) {
            fields[index] = updated
        } else {
            fields.append(updated)
        }
        return "---\n\(fields.joined(separator: "\n"))\n---\n\n\(text)\n"
    }

    /// - Returns: A nil front matter for a file that has none, and an empty one for a file whose front matter has no fields.
    private static func split(_ contents: String) -> (frontMatter: Substring?, body: Substring) {
        let opening = "---\n"
        guard contents.hasPrefix(opening) else { return (nil, contents[...]) }
        let rest = contents.dropFirst(opening.count)
        if rest.hasPrefix(opening) {
            return ("", rest.dropFirst(opening.count))
        }
        guard let closing = rest.range(of: "\n---\n") else { return (nil, contents[...]) }
        return (rest[..<closing.lowerBound], rest[closing.upperBound...])
    }

    private static func date(of field: String, in frontMatter: Substring?) -> Date? {
        let key = "\(field):"
        guard let line = frontMatter?.split(separator: "\n").first(where: { $0.hasPrefix(key) }) else { return nil }
        return try? Date(line.dropFirst(key.count).trimmingCharacters(in: .whitespaces), strategy: Note.createdStyle(in: .gmt))
    }
}

func fileNameStart(of path: String) -> String.Index {
    path.lastIndex(of: "/").map(path.index(after:)) ?? path.startIndex
}
