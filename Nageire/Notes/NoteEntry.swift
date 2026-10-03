import Foundation

/// A note as the list shows it: the text without its front matter, and when it was written.
struct NoteEntry: Identifiable, Hashable {
    let path: String
    let body: String
    let createdAt: Date?
    let isPending: Bool

    var id: String { path }

    init(path: String, contents: String, isPending: Bool) {
        self.path = path
        self.isPending = isPending
        let (frontMatter, text) = Self.split(contents)
        body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A file that reached the repository some other way may have no front matter.
        // The app's own file names still carry the time; any other file is listed without one.
        createdAt = Self.created(in: frontMatter) ?? Note.timeOfWriting(inFileName: path[fileNameStart(of: path)...])
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

    private static func split(_ contents: String) -> (frontMatter: Substring, body: Substring) {
        let opening = "---\n"
        guard contents.hasPrefix(opening) else { return ("", contents[...]) }
        let rest = contents.dropFirst(opening.count)
        if rest.hasPrefix(opening) {
            return ("", rest.dropFirst(opening.count))
        }
        guard let closing = rest.range(of: "\n---\n") else { return ("", contents[...]) }
        return (rest[..<closing.lowerBound], rest[closing.upperBound...])
    }

    private static func created(in frontMatter: Substring) -> Date? {
        let key = "created:"
        guard let line = frontMatter.split(separator: "\n").first(where: { $0.hasPrefix(key) }) else { return nil }
        return try? Date(line.dropFirst(key.count).trimmingCharacters(in: .whitespaces), strategy: Note.createdStyle(in: .gmt))
    }
}

private func fileNameStart(of path: String) -> String.Index {
    path.lastIndex(of: "/").map(path.index(after:)) ?? path.startIndex
}
