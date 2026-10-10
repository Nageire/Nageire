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
    /// The repository paths of the files of notes that GitHub does not have yet.
    private(set) var waitingAttachments: [String] = []
    var pendingCount: Int { pending.count + changes.count + waitingAttachments.count }
    /// While true, a note that links a waiting photo waits with its files, and the other notes go past it.
    /// The switch in Settings is on and the device is off Wi-Fi.
    var holdsPhotos = false
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
    /// The files attached in this launch to a note whose edit linking them is not recorded yet. A send leaves them
    /// alone, which would otherwise find them linked by no line and remove them while the edit is still being typed.
    private var attachedBeforeTheirEdit: Set<String> = []

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

    /// Keeps a file in the folder beside the note, under its own name, and returns the line that links to it.
    func attach(_ contents: Data, named name: String, to entry: NoteEntry) throws -> String {
        let folder = String(entry.folderPath)
        let fileName = Attachment.fileName(for: name, avoiding: Set(try store.attachmentNames(inFolder: folder)))
        let path = "\(folder)/\(fileName)"
        try store.addAttachment(StoredFile(path: path, contents: contents))
        attachedBeforeTheirEdit.insert(path)
        refreshPending()
        return Attachment.line(name: fileName, folder: entry.folderName)
    }

    private func change(_ entry: NoteEntry, to change: NoteChange) throws {
        try store.record(change)
        let folder = entry.folderPath + "/"
        attachedBeforeTheirEdit = attachedBeforeTheirEdit.filter { !$0.hasPrefix(folder) }
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
    /// A note's files go before it, so that the note on GitHub never links a file that is not there, and the files of its folder
    /// that it no longer links go after it. A note whose photos are held waits with them, and the others go past it.
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
        var held: Set<String> = []
        while let destination {
            do {
                let entry: NoteEntry
                let sendNote: () async throws -> Void
                if let note = try store.pending().first(where: { !held.contains($0.repositoryPath) }) {
                    entry = NoteEntry(path: note.repositoryPath, contents: note.contents, isPending: true)
                    sendNote = { try await self.send(note, to: destination) }
                } else if let change = try store.changes().first(where: { !held.contains($0.path) }) {
                    entry = Self.entry(after: change)
                    sendNote = { try await self.send(change, to: destination) }
                } else {
                    try removeStrandedAttachments()
                    return
                }
                let linked = entry.linkedAttachments
                let files = try store.waitingAttachments().filter(linked.contains)
                if holdsPhotos, files.contains(where: Attachment.isPhoto) {
                    held.insert(entry.path)
                    continue
                }
                try await sendAttachments(files, to: destination)
                try await sendNote()
                try await removeAttachments(of: entry, except: linked, in: destination)
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

    /// The note as GitHub holds it once the change is taken; a deleted note links nothing.
    private static func entry(after change: NoteChange) -> NoteEntry {
        switch change {
        case let .update(path, contents): NoteEntry(path: path, contents: String(decoding: contents, as: UTF8.self), isPending: true)
        case let .delete(path): NoteEntry(path: path, contents: "", isPending: true)
        }
    }

    private func sendAttachments(_ paths: [String], to destination: Repository) async throws {
        for path in paths {
            guard let contents = try store.attachment(at: path) else { continue }
            // Written over whatever the path holds, which is this note's file as another device sent it: the one
            // that arrives last wins, as for the note. A new note that turns out to share its name with another
            // device's note writes into that note's folder, since only the note is renamed, once GitHub refuses it.
            try await api.writeFile(at: path, in: destination, content: contents, message: "Add \(path[fileNameStart(of: path)...])")
            try store.markAttachmentSent(path: path)
            // The count goes down file by file, since a photo can take a while.
            waitingAttachments.removeAll { $0 == path }
        }
    }

    /// Removes the files of the note's folder outside `linked`: a waiting one from the device, a sent one from GitHub too.
    private func removeAttachments(of entry: NoteEntry, except linked: Set<String>, in destination: Repository) async throws {
        // A change recorded during the send may link a file the sent text does not; it is sent next and removes what it leaves.
        guard try pendingNote(at: entry.path) == nil, try !store.changes().contains(where: { $0.path == entry.path }) else { return }
        let folder = String(entry.folderPath)
        let waiting = Set(try store.waitingAttachments())
        for name in try store.attachmentNames(inFolder: folder) {
            let path = "\(folder)/\(name)"
            guard !linked.contains(path), !attachedBeforeTheirEdit.contains(path) else { continue }
            if waiting.contains(path) {
                try store.removeWaitingAttachment(path: path)
            } else {
                try await api.deleteFile(at: path, in: destination, message: "Delete \(name)")
                try store.removeFromLibrary(path: path)
            }
            waitingAttachments.removeAll { $0 == path }
        }
    }

    /// Removes the waiting files of notes with nothing waiting, whose line was taken out before an edit was recorded:
    /// no send of their note would otherwise ever come, and they would count as unsent for good.
    private func removeStrandedAttachments() throws {
        let waitingNotes = Set(try store.pending().map(\.repositoryPath) + store.changes().map(\.path))
        for path in try store.waitingAttachments() where !attachedBeforeTheirEdit.contains(path) {
            // The note is the folder with `.md`, and a note sent never links a file that did not go before it.
            let note = "\(path[..<fileNameStart(of: path)].dropLast()).md"
            guard !waitingNotes.contains(note) else { continue }
            try store.removeWaitingAttachment(path: path)
            waitingAttachments.removeAll { $0 == path }
        }
    }

    private func pendingNote(at path: String) throws -> Note? {
        try store.pending().first { $0.repositoryPath == path }
    }

    private func refreshPending() {
        pending = (try? store.pending()) ?? pending
        changes = (try? store.changes()) ?? changes
        waitingAttachments = (try? store.waitingAttachments()) ?? waitingAttachments
    }
}
