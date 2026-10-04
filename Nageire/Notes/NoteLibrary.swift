import Foundation
import Observation

/// The device's copy of the notes GitHub holds.
@Observable
final class NoteLibrary {
    /// Newest first.
    private(set) var sent: [NoteEntry] = []
    private(set) var lastRefreshFailed = false

    private let store: NoteStore
    private let api: GitHubAPI
    /// The repository a refresh is reading now.
    private var refreshing: Repository?
    private var requestedRepository: Repository?
    /// Counts the times the copy was emptied, so that a refresh begun before that can tell its result is for a repository no longer shown.
    private var generation = 0

    init(store: NoteStore, api: GitHubAPI) {
        self.store = store
        self.api = api
        sent = Self.entries(of: (try? store.library()) ?? [])
    }

    /// The notes for the list: the copy of what GitHub holds, with what is still waiting to be sent laid over it.
    func notes(including pending: [Note] = [], unsent changes: [NoteChange] = []) -> [NoteEntry] {
        guard !pending.isEmpty || !changes.isEmpty else { return sent }
        // The copy itself stays what GitHub holds, so a refresh needs no knowledge of the changes
        // and cannot undo one. A pending note is replaced as well: when its commit landed and
        // only the response was lost, a refresh has fetched it, and it would be listed twice.
        var unsent = pending.map { NoteEntry(path: $0.repositoryPath, contents: $0.contents, isPending: true) }
        var replaced = Set(unsent.map(\.path))
        for change in changes {
            replaced.insert(change.path)
            if case let .update(path, contents) = change {
                unsent.append(NoteEntry(path: path, contents: String(decoding: contents, as: UTF8.self), isPending: true))
            }
        }
        return (sent.filter { !replaced.contains($0.path) } + unsent).sorted { NoteEntry.isNewer($0, $1) }
    }

    /// Adds a note this device has just sent, which saves fetching it back.
    func add(_ note: Note) {
        list(path: note.repositoryPath, contents: note.contents)
    }

    /// Brings the list up to a change GitHub has just taken from this device.
    func apply(_ change: NoteChange) {
        switch change {
        case let .update(path, contents):
            list(path: path, contents: String(decoding: contents, as: UTF8.self))
        case let .delete(path):
            sent.removeAll { $0.path == path }
        }
        // A refresh under way may have listed the repository before the change landed there,
        // and would put the note back as it was. Another one after it sets that right.
        if let refreshing, requestedRepository == nil {
            requestedRepository = refreshing
        }
    }

    /// Brings the device's copy in line with the repository: fetches what is new or changed, drops what is gone.
    func refresh(from repository: Repository) async {
        // A request made during a refresh is not dropped: it may name another repository,
        // and the list would otherwise stay on the previous one until the next request.
        requestedRepository = repository
        guard refreshing == nil else { return }
        defer { refreshing = nil }
        while let repository = requestedRepository {
            requestedRepository = nil
            refreshing = repository
            await bringInLine(with: repository)
        }
    }

    func removeAll() {
        generation += 1
        try? store.removeLibrary()
        sent = []
        lastRefreshFailed = false
    }

    private func bringInLine(with repository: Repository) async {
        let generation = generation
        do {
            // The local side is read before the remote side. A note sent while this runs is then
            // in neither list, and is left alone instead of being dropped as "gone from GitHub".
            let local = Dictionary(uniqueKeysWithValues: try store.library().map { ($0.path, RemoteFile.sha(of: $0.contents)) })
            let remote = try await api.noteFiles(in: repository)
            guard generation == self.generation else { return }

            let gone = Set(local.keys).subtracting(remote.map(\.path))
            let changed = remote.filter { local[$0.path] != $0.sha }
            for path in gone {
                try store.removeFromLibrary(path: path)
            }
            // One request per file is the slow part of a first refresh, so several run at once.
            try await withThrowingTaskGroup(of: StoredFile.self) { group in
                var waiting = changed[...]
                func startNext() {
                    guard let file = waiting.popFirst() else { return }
                    group.addTask { @MainActor in
                        StoredFile(path: file.path, contents: try await self.api.blob(file.sha, in: repository))
                    }
                }
                for _ in 0..<6 { startNext() }
                while let file = try await group.next() {
                    guard generation == self.generation else {
                        group.cancelAll()
                        return
                    }
                    try store.saveToLibrary(file)
                    startNext()
                }
            }
            guard generation == self.generation else { return }
            if !gone.isEmpty || !changed.isEmpty {
                // Read from the store, not built from the snapshot above: a note sent during
                // the fetches is in the store and in the list, and must stay in the list.
                sent = Self.entries(of: try store.library())
            }
            lastRefreshFailed = false
        } catch {
            guard generation == self.generation else { return }
            // Files fetched before the failure are on the device; show them.
            sent = Self.entries(of: (try? store.library()) ?? [])
            lastRefreshFailed = true
        }
    }

    private func list(path: String, contents: String) {
        sent.removeAll { $0.path == path }
        sent.append(NoteEntry(path: path, contents: contents, isPending: false))
        sent.sort { NoteEntry.isNewer($0, $1) }
    }

    private static func entries(of files: [StoredFile]) -> [NoteEntry] {
        files
            .map { NoteEntry(path: $0.path, contents: String(decoding: $0.contents, as: UTF8.self), isPending: false) }
            .sorted { NoteEntry.isNewer($0, $1) }
    }
}

extension [NoteEntry] {
    func matching(_ query: String) -> [NoteEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? self : filter { $0.body.localizedStandardContains(query) }
    }
}
