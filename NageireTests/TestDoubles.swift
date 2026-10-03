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

    func currentUserLogin() async throws -> String { try login.get() }
    func installedRepositories() async throws -> [Repository] { try repositories.get() }
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
