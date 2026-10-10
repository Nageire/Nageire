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
    /// What the list and the note's header call the note: its first heading, or the start of its first line.
    let displayTitle: String
    /// The title is a heading the person wrote, not a line cut short.
    let hasHeading: Bool
    /// The text after the title, with the Markdown marks taken out, one line per line of the note.
    let excerpt: String
    /// The files the note links to beside itself, as `![name](<folder>/name)` lines.
    let attachmentCount: Int

    var id: String { path }

    /// The directory the note is in, `notes/YYYY/MM/`, which its image lines link from.
    var directory: Substring { path[..<fileNameStart(of: path)] }
    /// The folder beside the note, where its files are: the note's path without `.md`.
    var folderPath: Substring { path.hasSuffix(".md") ? path.dropLast(3) : Substring(path) }
    var folderName: Substring { folderPath[fileNameStart(of: path)...] }

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
        (displayTitle, hasHeading, excerpt, attachmentCount) = Self.summary(of: body)
    }

    /// The longest a title cut from a first line that is not a heading can be.
    static let titleLength = 40

    /// A heading on the first line is the title as written. Any other first line of text is cut at
    /// the end of its first sentence or at `titleLength` characters, and the rest of the line opens
    /// the excerpt. A note has no title field, so its first words serve, and a person who wants a
    /// real title writes a heading. A note that is an image and nothing else is called by the file's name.
    private static func summary(of body: String) -> (title: String, hasHeading: Bool, excerpt: String, attachments: Int) {
        var title: String?
        var hasHeading = false
        var excerpt: [String] = []
        var attachments = 0
        var firstFile: String?
        for line in body.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let markdown = MarkdownLine(line)
            // An image line is nothing to read, since its name is not text.
            if line.hasPrefix("![") {
                if case let .image(file, path) = markdown.kind, isAttachmentLink(decoded(path)) {
                    attachments += 1
                    firstFile = firstFile ?? file
                }
                continue
            }
            let text = plainText(of: markdown, in: line)
            guard !text.isEmpty else { continue }
            if title != nil {
                excerpt.append(text)
            } else if markdown.kind == .heading(level: 1) {
                title = text
                hasHeading = true
            } else {
                let sentenceEnd = text.firstMatch(of: sentenceEnd)?.range.upperBound ?? text.endIndex
                let cut = min(sentenceEnd, text.prefix(titleLength).endIndex)
                title = String(text[..<cut])
                let rest = text[cut...].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { excerpt.append(rest) }
            }
        }
        return (title ?? firstFile ?? "", hasHeading, excerpt.joined(separator: "\n"), attachments)
    }

    /// A Japanese sentence mark, or a period that is followed by a space or ends the line, so that a decimal or an address does not end a sentence.
    private static let sentenceEnd = /[。！？!?]|\.(?=\s|$)/
    /// The line without its Markdown marks: the block marker, emphasis and code marks, and a link's marks and address.
    private static func plainText(of markdown: MarkdownLine, in line: String) -> String {
        var text = line[markdown.prefix.upperBound...]
        for span in markdown.spans.reversed() where [.mark, .linkMark, .linkAddress].contains(span.role) {
            text.removeSubrange(span.range)
        }
        return String(text)
    }

    /// Orders by the time shown in the list. Files without a time come last, and the file name settles ties.
    static func isNewer(_ a: NoteEntry, _ b: NoteEntry) -> Bool {
        switch (a.createdAt, b.createdAt) {
        case let (a?, b?) where a != b: a > b
        case (_?, nil): true
        case (nil, _?): false
        default: a.path[fileNameStart(of: a.path)...] > b.path[fileNameStart(of: b.path)...]
        }
    }

    /// The repository path of the file an image line links to. Nil for a link that points out of the note's directory.
    func attachmentPath(linked link: String) -> String? {
        let link = Self.decoded(link)
        guard Self.isAttachmentLink(link) else { return nil }
        return directory + link
    }

    /// The repository paths of the files in the note's folder that any link of the note names: an image line, and also
    /// an image in a list item or beside a caption, or a plain link. A file outside this set is removed when the note is sent.
    var linkedAttachments: Set<String> {
        let folder = folderPath + "/"
        return Set(body.matches(of: Self.linkAddress).compactMap { match in
            attachmentPath(linked: String(match.output.1)).flatMap { $0.hasPrefix(folder) ? $0 : nil }
        })
    }

    /// The address of a Markdown link or image, up to a space before its title.
    private static let linkAddress = /\]\(([^)\s]+)/

    /// Another tool may have written the name with its spaces encoded. Decoded before the link is judged, so that an encoded `..` is judged as `..`.
    private static func decoded(_ link: String) -> String {
        link.removingPercentEncoding ?? link
    }

    /// A link with a scheme points elsewhere, as does one that starts at the root or climbs out of the directory.
    private static func isAttachmentLink(_ link: String) -> Bool {
        !link.contains("://") && !link.hasPrefix("/") && !link.split(separator: "/").contains("..")
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
