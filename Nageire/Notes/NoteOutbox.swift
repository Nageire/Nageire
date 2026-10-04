import Foundation
import Observation

/// Saves notes on the device first and sends them to GitHub afterwards.
@Observable
final class NoteOutbox {
    /// The repository pending notes and changes are sent to. Read before each one, so a change of repository takes effect within a pass.
    var destination: Repository? {
        didSet { wasRefused = false }
    }

    /// The notes not yet sent, oldest first.
    private(set) var pending: [Note] = []
    /// The edits and deletions of notes GitHub holds that are not yet sent.
    private(set) var changes: [NoteChange] = []
    var pendingCount: Int { pending.count + changes.count }
    /// Called with each note GitHub has taken.
    var onSent: (Note) -> Void = { _ in }
    /// Called with each edit or deletion GitHub has taken.
    var onChanged: (NoteChange) -> Void = { _ in }
    /// GitHub refused the last note or change in a way that waiting will not fix, for example after the GitHub App was removed from the repository.
    private(set) var wasRefused = false

    private let store: NoteStore
    private let api: GitHubAPI
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let suffix: () -> String
    private var isSending = false

    init(
        store: NoteStore,
        api: GitHubAPI,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { .current },
        suffix: @escaping () -> String = { Note.randomSuffix() }
    ) {
        self.store = store
        self.api = api
        self.now = now
        self.timeZone = timeZone
        self.suffix = suffix
        refreshPending()
    }

    func add(body: String) throws {
        try store.add(Note(body: body, createdAt: now(), timeZone: timeZone(), suffix: suffix()))
        refreshPending()
    }

    /// Replaces the text of a note. An unchanged text is not an edit: it would still move `updated` and add a commit.
    func edit(_ entry: NoteEntry, text: String) throws {
        guard Note.trimmed(text) != entry.editableText else { return }
        let contents = entry.contents(withText: text, updatedAt: now(), timeZone: timeZone())
        try change(entry, to: .update(path: entry.path, contents: Data(contents.utf8)))
    }

    func delete(_ entry: NoteEntry) throws {
        try change(entry, to: .delete(path: entry.path))
    }

    private func change(_ entry: NoteEntry, to change: NoteChange) throws {
        try store.record(change)
        // A note still pending may be on GitHub already: its commit can land while the response
        // is lost, or be in flight now. So it stops being pending, and the change is applied to
        // whatever the path turns out to hold. Rewriting the pending note instead would have
        // the next attempt meet different content at its path and add the note a second time.
        if let note = try pendingNote(at: entry.path) {
            try store.removePending(note)
        }
        refreshPending()
    }

    /// Sends the pending notes oldest first, then the changes, and stops at the first one GitHub does not take; the rest wait for the next call.
    func send() async {
        // The Contents API rejects a commit made while another one to the same branch is in
        // flight, so there is one pass at a time. The pass reads the store again before each
        // request, which is how it picks up a note added while it runs.
        guard !isSending else { return }
        isSending = true
        defer {
            isSending = false
            refreshPending()
        }
        while let destination {
            do {
                if let note = try store.pending().first {
                    try await send(note, to: destination)
                } else if let change = try store.changes().first {
                    try await send(change, to: destination)
                } else {
                    return
                }
            } catch let GitHubAPIError.unexpectedStatus(status) where !Self.transientStatuses.contains(status) {
                wasRefused = true
                return
            } catch {
                return
            }
        }
    }

    /// 409 is a commit racing another writer to the branch, and 429 is rate limiting; both pass on their own.
    private static let transientStatuses: Set<Int> = Set([409, 429]).union(500..<600)

    private func send(_ note: Note, to destination: Repository) async throws {
        do {
            try await api.createFile(
                at: note.repositoryPath,
                in: destination,
                content: Data(note.contents.utf8),
                message: "Add \(note.fileName)"
            )
        } catch GitHubAPIError.fileAlreadyExists {
            // Another device wrote a different note in the same second and drew the same suffix.
            try store.replacePending(note, with: note.renamed(suffix: suffix()))
            return
        }
        // A note edited or deleted during the request is no longer pending, and the change
        // recorded for it is sent next.
        if try pendingNote(at: note.repositoryPath) != nil {
            try store.markSent(note)
            refreshPending()
            onSent(note)
        }
        wasRefused = false
    }

    private func send(_ change: NoteChange, to destination: Repository) async throws {
        switch change {
        case let .update(path, contents):
            try await api.writeFile(at: path, in: destination, content: contents, message: "Update \(change.fileName)")
        case let .delete(path):
            try await api.deleteFile(at: path, in: destination, message: "Delete \(change.fileName)")
        }
        try store.resolve(change)
        wasRefused = false
        refreshPending()
        onChanged(change)
    }

    private func pendingNote(at path: String) throws -> Note? {
        try store.pending().first { $0.repositoryPath == path }
    }

    private func refreshPending() {
        pending = (try? store.pending()) ?? pending
        changes = (try? store.changes()) ?? changes
    }
}
