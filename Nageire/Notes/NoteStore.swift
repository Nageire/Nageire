import Foundation

protocol NoteStore {
    func add(_ note: Note) throws
    func pendingCount() throws -> Int
    /// The oldest note not yet sent to GitHub.
    func firstPending() throws -> Note?
    func markSent(_ note: Note) throws
    /// Swaps a pending note for the same note under a different name.
    func replacePending(_ note: Note, with replacement: Note) throws
}

/// Keeps every note as a file on the device: `outbox` until GitHub has it, `sent` afterwards.
struct FileNoteStore: NoteStore {
    let directory: URL

    private var outbox: URL { directory.appending(path: "outbox", directoryHint: .isDirectory) }
    private var sent: URL { directory.appending(path: "sent", directoryHint: .isDirectory) }

    func add(_ note: Note) throws {
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        try Data(note.contents.utf8).write(to: outbox.appending(path: note.fileName), options: .atomic)
    }

    func pendingCount() throws -> Int {
        try pendingFileNames().count
    }

    func firstPending() throws -> Note? {
        guard let fileName = try pendingFileNames().min() else { return nil }
        return Note(fileName: fileName, contents: try String(contentsOf: outbox.appending(path: fileName), encoding: .utf8))
    }

    func markSent(_ note: Note) throws {
        try FileManager.default.createDirectory(at: sent, withIntermediateDirectories: true)
        let destination = sent.appending(path: note.fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: outbox.appending(path: note.fileName), to: destination)
    }

    func replacePending(_ note: Note, with replacement: Note) throws {
        // The two differ in name only, so one move swaps them with no moment at which both are pending.
        try FileManager.default.moveItem(at: outbox.appending(path: note.fileName), to: outbox.appending(path: replacement.fileName))
    }

    private func pendingFileNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: outbox.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: outbox.path).filter { $0.hasSuffix(".md") }
    }
}
