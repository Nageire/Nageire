import Foundation
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

    func createFile(at path: String, in repository: Repository, content: Data, message: String) async throws {
        createFileAttempts.append(CreatedFile(path: path, repository: repository.fullName, content: String(decoding: content, as: UTF8.self), message: message))
        await Task.yield()
        if !createFileResults.isEmpty {
            try createFileResults.removeFirst().get()
        }
    }
}

@MainActor
final class InMemoryNoteStore: NoteStore {
    private(set) var outbox: [Note] = []
    private(set) var sent: [Note] = []

    func add(_ note: Note) throws { outbox.append(note) }
    func pendingCount() throws -> Int { outbox.count }
    func firstPending() throws -> Note? { outbox.min { $0.fileName < $1.fileName } }

    func markSent(_ note: Note) throws {
        outbox.removeAll { $0 == note }
        sent.append(note)
    }

    func replacePending(_ note: Note, with replacement: Note) throws {
        outbox.removeAll { $0 == note }
        outbox.append(replacement)
    }
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
