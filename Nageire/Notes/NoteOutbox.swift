import Foundation
import Observation

/// Saves notes on the device first and sends them to GitHub afterwards.
@Observable
final class NoteOutbox {
    /// The repository pending notes are sent to. Read before each note, so a change takes effect within a pass.
    var destination: Repository? {
        didSet { wasRefused = false }
    }

    /// The notes not yet sent, oldest first.
    private(set) var pending: [Note] = []
    var pendingCount: Int { pending.count }
    /// Called with each note GitHub has taken.
    var onSent: (Note) -> Void = { _ in }
    /// GitHub refused the last note in a way that waiting will not fix, for example after the GitHub App was removed from the repository.
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

    /// Sends the pending notes oldest first and stops at the first one GitHub does not take; the rest wait for the next call.
    func send() async {
        // The Contents API rejects a commit made while another one to the same branch is in
        // flight, so there is one pass at a time. The pass reads the store again before each
        // note, which is how it picks up a note added while it runs.
        guard !isSending else { return }
        isSending = true
        defer {
            isSending = false
            refreshPending()
        }
        while let destination, let note = try? store.pending().first {
            do {
                try await api.createFile(
                    at: note.repositoryPath,
                    in: destination,
                    content: Data(note.contents.utf8),
                    message: "Add \(note.fileName)"
                )
                try store.markSent(note)
                wasRefused = false
                refreshPending()
                onSent(note)
            } catch GitHubAPIError.fileAlreadyExists {
                // Another device wrote a different note in the same second and drew the same suffix.
                guard (try? store.replacePending(note, with: note.renamed(suffix: suffix()))) != nil else { return }
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

    private func refreshPending() {
        pending = (try? store.pending()) ?? pending
    }
}
