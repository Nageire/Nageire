import Foundation
import UniformTypeIdentifiers

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

    /// The line that links the file from the note, relative to the note's directory: an image, so that GitHub's file view
    /// shows it, or for any other file a link, which GitHub would otherwise draw as a broken image.
    static func line(name: String, folder: some StringProtocol) -> String {
        "\(isPhoto(name) ? "!" : "")[\(name)](\(folder)/\(name))"
    }

    /// Above this the app asks before keeping a file, as ux-redesign.md decides: it is slow to send and makes the repository large.
    static let largeSize = 25_000_000
    /// Above this the Contents API refuses the file, so the app does not keep it.
    static let maximumSize = 100_000_000

    enum SizeCheck: Equatable {
        case fine
        case large
        case tooLarge
    }

    /// What the app does with a file of the size before keeping it. A photo it reduces is fine at any size.
    static func check(size: Int, name: String?) -> SizeCheck {
        if Photo.isReduced(name) || size <= largeSize {
            .fine
        } else if size <= maximumSize {
            .large
        } else {
            .tooLarge
        }
    }

    /// A file the switch for Wi-Fi holds back, and that is linked as an image: an image, by its name's extension. An SVG is one,
    /// since GitHub shows it as one, though the editor's thumbnail stays its frame.
    static func isPhoto(_ path: String) -> Bool {
        type(of: path)?.conforms(to: .image) == true
    }

    /// The type of a file, by its name's extension.
    static func type(of path: String) -> UTType? {
        UTType(filenameExtension: (path as NSString).pathExtension)
    }

    /// Replaced by `_`: the characters a path cannot carry on either platform or on GitHub, the brackets and
    /// parentheses a Markdown link reads as its own, whitespace, which ends a link's address, `%`, which a reader
    /// of the link takes for an escape, and `#`, after which a browser takes the rest for a fragment.
    private static func replaced(_ character: Character) -> Bool {
        character.isWhitespace || "/\\:*?\"<>|()[]%#".contains(character)
            || character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
