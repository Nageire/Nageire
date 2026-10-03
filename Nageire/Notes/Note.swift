import Foundation

/// A note as the file it is stored as, on the device and in the repository.
struct Note: Equatable, Identifiable {
    let fileName: String
    let contents: String

    var id: String { fileName }

    /// The month directory comes from the UTC timestamp in the file name, so the user is never asked where a note goes.
    var repositoryPath: String {
        let year = fileName.prefix(4)
        let month = fileName.dropFirst(5).prefix(2)
        return "notes/\(year)/\(month)/\(fileName)"
    }
}

extension Note {
    /// - Parameter suffix: Tells apart notes written on two devices within the same second.
    init(body: String, createdAt: Date, timeZone: TimeZone, suffix: String) {
        // UTC in the name keeps name order equal to writing order across time zones.
        // The local time of writing would be lost that way, so the front matter carries it.
        let stamp = createdAt.formatted(Date.ISO8601FormatStyle(timeSeparator: .omitted, timeZone: .gmt))
        let created = createdAt.formatted(Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: timeZone))
        // Blank lines around the text go, but the first line keeps its indentation:
        // in Markdown it can mark a code block or a nested list item.
        var text = body.split(separator: "\n", omittingEmptySubsequences: false)
            .drop { $0.allSatisfy(\.isWhitespace) }
            .joined(separator: "\n")
        while text.last?.isWhitespace == true {
            text.removeLast()
        }
        self.init(fileName: "\(stamp)-\(suffix).md", contents: "---\ncreated: \(created)\n---\n\n\(text)\n")
    }

    func renamed(suffix: String) -> Note {
        // The suffix is the four characters between the last hyphen and ".md".
        Note(fileName: "\(fileName.dropLast(7))\(suffix).md", contents: contents)
    }

    static func randomSuffix() -> String {
        String(format: "%04x", UInt16.random(in: .min ... .max))
    }
}
