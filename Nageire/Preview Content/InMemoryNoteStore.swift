#if DEBUG
import Foundation

/// Keeps the notes in memory and writes no file, for the tests and for the sample the app can run on.
final class InMemoryNoteStore: NoteStore {
    private(set) var outbox: [Note]
    private(set) var files: [String: Data] = [:]

    private(set) var recorded: [NoteChange] = []

    init(pending: [Note] = []) {
        outbox = pending
    }

    func add(_ note: Note) throws { outbox.append(note) }
    func pending() throws -> [Note] { outbox.sorted { $0.fileName < $1.fileName } }

    func markSent(_ note: Note) throws {
        outbox.removeAll { $0 == note }
        files[note.repositoryPath] = Data(note.contents.utf8)
    }

    func replacePending(_ note: Note, with replacement: Note) throws {
        outbox.removeAll { $0 == note }
        outbox.append(replacement)
    }

    func removePending(_ note: Note) throws { outbox.removeAll { $0 == note } }

    /// In the order `FileNoteStore` gives: updates before deletions, each in path order.
    func changes() throws -> [NoteChange] {
        recorded.sorted { a, b in
            switch (a, b) {
            case (.update, .delete): true
            case (.delete, .update): false
            default: a.path < b.path
            }
        }
    }

    func record(_ change: NoteChange) throws {
        recorded.removeAll { $0.path == change.path }
        recorded.append(change)
    }

    func resolve(_ change: NoteChange) throws {
        switch change {
        case let .update(path, contents): files[path] = contents
        case let .delete(path): files[path] = nil
        }
        recorded.removeAll { $0 == change }
    }

    func library() throws -> [StoredFile] { files.map { StoredFile(path: $0.key, contents: $0.value) } }
    func saveToLibrary(_ file: StoredFile) throws { files[file.path] = file.contents }
    func removeFromLibrary(path: String) throws { files[path] = nil }
    func removeLibrary() throws { files = [:] }
}
#endif
