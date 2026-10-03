import CryptoKit
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
    private var isRefreshing = false
    private var requestedRepository: Repository?
    /// Counts the times the copy was emptied, so that a refresh begun before that can tell its result is for a repository no longer shown.
    private var generation = 0

    init(store: NoteStore, api: GitHubAPI) {
        self.store = store
        self.api = api
        sent = Self.entries(of: (try? store.library()) ?? [])
    }

    /// The notes for the list: the copy of what GitHub holds together with the notes still waiting to be sent.
    func notes(including pending: [Note] = [], matching query: String = "") -> [NoteEntry] {
        var all = sent
        if !pending.isEmpty {
            // A note whose commit landed while its response was lost is on GitHub and still pending
            // here. A refresh then fetches it, and it would be listed twice under one path.
            let pendingPaths = Set(pending.map(\.repositoryPath))
            all.removeAll { pendingPaths.contains($0.path) }
            all += pending.map { NoteEntry(path: $0.repositoryPath, contents: $0.contents, isPending: true) }
            all.sort { NoteEntry.isNewer($0, $1) }
        }
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? all : all.filter { $0.body.localizedStandardContains(query) }
    }

    /// Adds a note this device has just sent, which saves fetching it back.
    func add(_ note: Note) {
        sent.removeAll { $0.path == note.repositoryPath }
        sent.append(NoteEntry(path: note.repositoryPath, contents: note.contents, isPending: false))
        sent.sort { NoteEntry.isNewer($0, $1) }
    }

    /// Brings the device's copy in line with the repository: fetches what is new or changed, drops what is gone.
    func refresh(from repository: Repository) async {
        // A request made during a refresh is not dropped: it may name another repository,
        // and the list would otherwise stay on the previous one until the next request.
        requestedRepository = repository
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        while let repository = requestedRepository {
            requestedRepository = nil
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
            let local = Dictionary(uniqueKeysWithValues: try store.library().map { ($0.path, Self.blobSHA(of: $0.contents)) })
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

    /// The identifier Git gives a file's content, which is what the repository's tree lists.
    /// Computing it locally tells an unchanged file from a changed one without keeping a separate index.
    static func blobSHA(of contents: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(contents.count)\0".utf8))
        hasher.update(data: contents)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func entries(of files: [StoredFile]) -> [NoteEntry] {
        files
            .map { NoteEntry(path: $0.path, contents: String(decoding: $0.contents, as: UTF8.self), isPending: false) }
            .sorted { NoteEntry.isNewer($0, $1) }
    }
}
