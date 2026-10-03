import Foundation

/// A file as the device holds it, at the path it has in the repository.
struct StoredFile: Equatable {
    let path: String
    let contents: Data
}

protocol NoteStore {
    func add(_ note: Note) throws
    /// The notes not yet sent to GitHub, oldest first.
    func pending() throws -> [Note]
    /// Moves a pending note into the library, at its repository path.
    func markSent(_ note: Note) throws
    /// Swaps a pending note for the same note under a different name.
    func replacePending(_ note: Note, with replacement: Note) throws

    /// The device's copy of the files GitHub holds.
    func library() throws -> [StoredFile]
    func saveToLibrary(_ file: StoredFile) throws
    func removeFromLibrary(path: String) throws
    func removeLibrary() throws
}

/// Keeps every note as a file on the device: `outbox` until GitHub has it, `library` for what GitHub holds.
struct FileNoteStore: NoteStore {
    let directory: URL

    private var outbox: URL { directory.appending(path: "outbox", directoryHint: .isDirectory) }
    private var libraryDirectory: URL { directory.appending(path: "library", directoryHint: .isDirectory) }

    func add(_ note: Note) throws {
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        try Data(note.contents.utf8).write(to: outbox.appending(path: note.fileName), options: .atomic)
    }

    func pending() throws -> [Note] {
        guard FileManager.default.fileExists(atPath: outbox.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: outbox.path)
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { Note(fileName: $0, contents: try String(contentsOf: outbox.appending(path: $0), encoding: .utf8)) }
    }

    func markSent(_ note: Note) throws {
        let destination = libraryDirectory.appending(path: note.repositoryPath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: outbox.appending(path: note.fileName), to: destination)
    }

    func replacePending(_ note: Note, with replacement: Note) throws {
        // The two differ in name only, so one move swaps them with no moment at which both are pending.
        try FileManager.default.moveItem(at: outbox.appending(path: note.fileName), to: outbox.appending(path: replacement.fileName))
    }

    func library() throws -> [StoredFile] {
        guard let paths = FileManager.default.subpaths(atPath: libraryDirectory.path) else { return [] }
        return try paths.filter { $0.hasSuffix(".md") }.map {
            StoredFile(path: $0, contents: try Data(contentsOf: libraryDirectory.appending(path: $0)))
        }
    }

    func saveToLibrary(_ file: StoredFile) throws {
        let destination = libraryDirectory.appending(path: file.path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.contents.write(to: destination, options: .atomic)
    }

    func removeFromLibrary(path: String) throws {
        try FileManager.default.removeItem(at: libraryDirectory.appending(path: path))
    }

    func removeLibrary() throws {
        guard FileManager.default.fileExists(atPath: libraryDirectory.path) else { return }
        try FileManager.default.removeItem(at: libraryDirectory)
    }
}
