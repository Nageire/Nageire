import Foundation
import Testing
@testable import Nageire

@MainActor
final class StubTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    var respond: (URLRequest) throws -> (Int, String)

    init(respond: @escaping (URLRequest) throws -> (Int, String)) {
        self.respond = respond
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = try respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

extension URLRequest {
    var formBody: [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = httpBody.map { String(decoding: $0, as: UTF8.self) }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

@MainActor
final class FakeOAuth: GitHubOAuth {
    var deviceCode: Result<DeviceCode, Error> = .success(.sample)
    var polls: [Result<DeviceTokenPoll, Error>] = []
    var refreshResult: Result<TokenGrant, Error> = .success(.sample)
    private(set) var refreshTokensUsed: [String] = []

    func requestDeviceCode() async throws -> DeviceCode {
        try deviceCode.get()
    }

    func pollToken(deviceCode: String) async throws -> DeviceTokenPoll {
        try polls.removeFirst().get()
    }

    func refresh(refreshToken: String) async throws -> TokenGrant {
        refreshTokensUsed.append(refreshToken)
        await Task.yield()
        return try refreshResult.get()
    }
}

@MainActor
final class InMemoryTokenStore: TokenStore {
    var tokens: TokenSet?

    init(tokens: TokenSet? = nil) {
        self.tokens = tokens
    }

    func load() throws -> TokenSet? { tokens }
    func save(_ tokens: TokenSet) throws { self.tokens = tokens }
    func delete() throws { tokens = nil }
}

@MainActor
final class FakeAPI: GitHubAPI {
    var login: Result<String, Error> = .success("octocat")
    var repositories: Result<[Repository], Error> = .success([])

    struct CreatedFile: Equatable {
        let path: String
        let repository: String
        let content: String
        let message: String
    }

    /// Consumed one per call; once empty, every call succeeds.
    var createFileResults: [Result<Void, Error>] = []
    private(set) var createFileAttempts: [CreatedFile] = []

    func currentUserLogin() async throws -> String { try login.get() }
    func installedRepositories() async throws -> [Repository] { try repositories.get() }

    /// What the repository holds, as path to content.
    var remoteNotes: Result<[String: String], Error> = .success([:])
    private(set) var fetchedBlobs: [String] = []

    private(set) var listedRepositories: [String] = []

    func noteFiles(in repository: Repository) async throws -> [RemoteFile] {
        listedRepositories.append(repository.fullName)
        await Task.yield()
        return try remoteNotes.get().map { RemoteFile(path: $0.key, sha: RemoteFile.sha(of: Data($0.value.utf8))) }
    }

    func blob(_ sha: String, in repository: Repository) async throws -> Data {
        fetchedBlobs.append(sha)
        await Task.yield()
        let contents = try remoteNotes.get().values.first { RemoteFile.sha(of: Data($0.utf8)) == sha }
        return Data(try #require(contents).utf8)
    }

    func createFile(at path: String, in repository: Repository, content: Data, message: String) async throws {
        createFileAttempts.append(CreatedFile(path: path, repository: repository.fullName, content: String(decoding: content, as: UTF8.self), message: message))
        await Task.yield()
        if !createFileResults.isEmpty {
            try createFileResults.removeFirst().get()
        }
        if var notes = try? remoteNotes.get() {
            notes[path] = String(decoding: content, as: UTF8.self)
            remoteNotes = .success(notes)
        }
    }

    struct DeletedFile: Equatable {
        let path: String
        let repository: String
        let message: String
    }

    /// Consumed one per call to `writeFile` or `deleteFile`; once empty, every call succeeds.
    var changeResults: [Result<Void, Error>] = []
    private(set) var writeFileAttempts: [CreatedFile] = []
    private(set) var deleteFileAttempts: [DeletedFile] = []

    func writeFile(at path: String, in repository: Repository, content: Data, message: String) async throws {
        let content = String(decoding: content, as: UTF8.self)
        writeFileAttempts.append(CreatedFile(path: path, repository: repository.fullName, content: content, message: message))
        try await change(path, to: content)
    }

    func deleteFile(at path: String, in repository: Repository, message: String) async throws {
        deleteFileAttempts.append(DeletedFile(path: path, repository: repository.fullName, message: message))
        try await change(path, to: nil)
    }

    private func change(_ path: String, to content: String?) async throws {
        await Task.yield()
        if !changeResults.isEmpty {
            try changeResults.removeFirst().get()
        }
        if var notes = try? remoteNotes.get() {
            notes[path] = content
            remoteNotes = .success(notes)
        }
    }
}

@MainActor
final class InMemoryNoteStore: NoteStore {
    private(set) var outbox: [Note] = []
    private(set) var files: [String: Data] = [:]

    private(set) var recorded: [NoteChange] = []

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

extension DeviceCode {
    static let sample = DeviceCode(
        deviceCode: "device-code",
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://github.com/login/device")!,
        interval: 5
    )
}

extension TokenGrant {
    static let sample = TokenGrant(accessToken: "access-new", expiresIn: 28800, refreshToken: "refresh-new")
}

extension TokenSet {
    static func sample(accessTokenExpiresAt: Date) -> TokenSet {
        TokenSet(accessToken: "access-old", accessTokenExpiresAt: accessTokenExpiresAt, refreshToken: "refresh-old")
    }
}
