import Foundation

/// A file of a note, kept in the folder beside the note, `notes/YYYY/MM/<timestamp>-<suffix>/<name>`, and linked from an image line.
nonisolated enum Attachment {
    /// The name the file is kept under: its own, with the characters a path or a Markdown link cannot carry replaced,
    /// and a counter before the extension when the folder already has the name.
    static func fileName(for original: String, avoiding taken: Set<String>) -> String {
        // The file system hands over decomposed names, which GitHub lists as other files than the precomposed ones.
        var name = String(original.precomposedStringWithCanonicalMapping.map { Self.replaced($0) ? "_" : $0 })
        // A leading dot hides the file on the device and in the repository's listing.
        if name.first == "." {
            name = "_" + name.dropFirst()
        }
        if name.isEmpty {
            name = "file"
        }
        guard taken.contains(name) else { return name }
        let stem = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension.isEmpty ? "" : ".\((name as NSString).pathExtension)"
        for counter in 2... {
            let candidate = "\(stem)-\(counter)\(suffix)"
            if !taken.contains(candidate) {
                return candidate
            }
        }
        preconditionFailure("The counter has no end.")
    }

    /// The line that links the file from the note, relative to the note's directory, so that GitHub's file view shows the image.
    static func line(name: String, folder: some StringProtocol) -> String {
        "![\(name)](\(folder)/\(name))"
    }

    /// Replaced by `_`: the characters a path cannot carry on either platform or on GitHub, the brackets and
    /// parentheses a Markdown link reads as its own, whitespace, which ends a link's address, `%`, which a reader
    /// of the link takes for an escape, and `#`, after which a browser takes the rest for a fragment.
    private static func replaced(_ character: Character) -> Bool {
        character.isWhitespace || "/\\:*?\"<>|()[]%#".contains(character)
            || character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
