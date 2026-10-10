import Foundation

/// A file as the device holds it, at the path it has in the repository.
struct StoredFile: Equatable {
    let path: String
    let contents: Data
}

/// A change to a note GitHub already holds, made on the device and waiting to be sent.
enum NoteChange: Equatable {
    case update(path: String, contents: Data)
    case delete(path: String)

    var path: String {
        switch self {
        case let .update(path, _), let .delete(path): path
        }
    }

    var fileName: Substring { path[fileNameStart(of: path)...] }
}

protocol NoteStore {
    func add(_ note: Note) throws
    /// The notes not yet sent to GitHub, oldest first.
    func pending() throws -> [Note]
    /// Moves a pending note into the library, at its repository path.
    func markSent(_ note: Note) throws
    /// Swaps a pending note for the same note under a different name.
    func replacePending(_ note: Note, with replacement: Note) throws
    func removePending(_ note: Note) throws

    /// The changes not yet sent to GitHub, at most one per path.
    func changes() throws -> [NoteChange]
    /// Takes the place of a change already waiting for the same path.
    func record(_ change: NoteChange) throws
    /// Brings the library up to a change GitHub has taken and stops the change waiting.
    /// A different change recorded for the path in the meantime stays.
    func resolve(_ change: NoteChange) throws

    /// Keeps a file of a note, at its repository path, until GitHub has it.
    func addAttachment(_ file: StoredFile) throws
    /// The names of the files in a note's folder that the device has: waiting, and in the library.
    func attachmentNames(inFolder folder: String) throws -> [String]
    /// A file of a note at its repository path, waiting or in the library. Nil when the device does not have it.
    func attachment(at path: String) throws -> Data?
    /// The repository paths of the files of notes not yet sent to GitHub, in path order.
    func waitingAttachments() throws -> [String]
    /// Moves a waiting file into the library, at its repository path.
    func markAttachmentSent(path: String) throws
    /// Deletes a waiting file that GitHub never got.
    func removeWaitingAttachment(path: String) throws

    /// The device's copy of the files GitHub holds.
    func library() throws -> [StoredFile]
    func saveToLibrary(_ file: StoredFile) throws
    func removeFromLibrary(path: String) throws
    func removeLibrary() throws
}

/// Keeps every note as a file on the device: `outbox` until GitHub has it, `library` for what GitHub holds,
/// `updates` and `deletions` for changes to what GitHub holds, and `attachments` for a note's files until GitHub has them.
struct FileNoteStore: NoteStore {
    let directory: URL

    private var outbox: URL { directory.appending(path: "outbox", directoryHint: .isDirectory) }
    private var attachments: URL { directory.appending(path: "attachments", directoryHint: .isDirectory) }
    private var libraryDirectory: URL { directory.appending(path: "library", directoryHint: .isDirectory) }
    // An update keeps the whole edited file outside the library, which is emptied at sign-out
    // while the edit still has to be sent.
    private var updates: URL { directory.appending(path: "updates", directoryHint: .isDirectory) }
    private var deletions: URL { directory.appending(path: "deletions", directoryHint: .isDirectory) }

    func add(_ note: Note) throws {
        try write(Data(note.contents.utf8), to: outbox.appending(path: note.fileName))
    }

    func pending() throws -> [Note] {
        guard FileManager.default.fileExists(atPath: outbox.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: outbox.path)
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { Note(fileName: $0, contents: try String(contentsOf: outbox.appending(path: $0), encoding: .utf8)) }
    }

    func markSent(_ note: Note) throws {
        try moveIntoLibrary(outbox.appending(path: note.fileName), at: note.repositoryPath)
    }

    func replacePending(_ note: Note, with replacement: Note) throws {
        // The two differ in name only, so one move swaps them with no moment at which both are pending.
        try FileManager.default.moveItem(at: outbox.appending(path: note.fileName), to: outbox.appending(path: replacement.fileName))
    }

    func removePending(_ note: Note) throws {
        try FileManager.default.removeItem(at: outbox.appending(path: note.fileName))
    }

    func changes() throws -> [NoteChange] {
        try files(in: updates).map { .update(path: $0.path, contents: $0.contents) }
            + files(in: deletions).map { .delete(path: $0.path) }
    }

    func record(_ change: NoteChange) throws {
        switch change {
        case let .update(path, contents):
            try write(contents, to: updates.appending(path: path))
            try? FileManager.default.removeItem(at: deletions.appending(path: path))
        case let .delete(path):
            try write(Data(), to: deletions.appending(path: path))
            try? FileManager.default.removeItem(at: updates.appending(path: path))
        }
    }

    func resolve(_ change: NoteChange) throws {
        switch change {
        case let .update(path, contents):
            try saveToLibrary(StoredFile(path: path, contents: contents))
            let file = updates.appending(path: path)
            guard (try? Data(contentsOf: file)) == contents else { return }
            try FileManager.default.removeItem(at: file)
        case let .delete(path):
            // Neither file is there when the library was emptied, or an edit was recorded, in the meantime.
            try? FileManager.default.removeItem(at: libraryDirectory.appending(path: path))
            try? FileManager.default.removeItem(at: deletions.appending(path: path))
        }
    }

    func addAttachment(_ file: StoredFile) throws {
        try write(file.contents, to: attachments.appending(path: file.path))
    }

    func attachmentNames(inFolder folder: String) throws -> [String] {
        try [attachments, libraryDirectory].flatMap { root -> [String] in
            do {
                return try FileManager.default.contentsOfDirectory(atPath: root.appending(path: folder).path)
            } catch CocoaError.fileReadNoSuchFile {
                return []
            }
        }
    }

    func attachment(at path: String) throws -> Data? {
        for root in [attachments, libraryDirectory] {
            do {
                // Mapped, since the bytes are read on the main actor and a photo has megabytes of them.
                return try Data(contentsOf: root.appending(path: path), options: .mappedIfSafe)
            } catch CocoaError.fileReadNoSuchFile {
                continue
            }
        }
        return nil
    }

    func waitingAttachments() throws -> [String] {
        try filePaths(in: attachments)
    }

    func markAttachmentSent(path: String) throws {
        try moveIntoLibrary(attachments.appending(path: path), at: path)
    }

    /// Deletes a waiting file that GitHub never got.
    func removeWaitingAttachment(path: String) throws {
        try FileManager.default.removeItem(at: attachments.appending(path: path))
    }

    func library() throws -> [StoredFile] {
        try files(in: libraryDirectory)
    }

    func saveToLibrary(_ file: StoredFile) throws {
        try write(file.contents, to: libraryDirectory.appending(path: file.path))
    }

    func removeFromLibrary(path: String) throws {
        try FileManager.default.removeItem(at: libraryDirectory.appending(path: path))
    }

    func removeLibrary() throws {
        guard FileManager.default.fileExists(atPath: libraryDirectory.path) else { return }
        try FileManager.default.removeItem(at: libraryDirectory)
    }

    /// The paths of the files under the directory, relative to it, in path order.
    private func filePaths(in directory: URL, where include: (URL) -> Bool = { _ in true }) throws -> [String] {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let root = directory.resolvingSymlinksInPath().pathComponents.count
        return files.compactMap { $0 as? URL }
            .filter { include($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.resolvingSymlinksInPath().pathComponents.dropFirst(root).joined(separator: "/") }
            .sorted()
    }

    /// The Markdown files under the directory, with their paths relative to it, in path order.
    private func files(in directory: URL) throws -> [StoredFile] {
        guard let paths = FileManager.default.subpaths(atPath: directory.path) else { return [] }
        return try paths.filter { $0.hasSuffix(".md") }.sorted().map {
            StoredFile(path: $0, contents: try Data(contentsOf: directory.appending(path: $0)))
        }
    }

    /// Moves the file to its repository path in the library, over what the library holds there.
    private func moveIntoLibrary(_ file: URL, at path: String) throws {
        let destination = libraryDirectory.appending(path: path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
    }

    private func write(_ contents: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, options: .atomic)
    }
}
