import Foundation
import Testing
@testable import Nageire

@MainActor
struct GitHubAPIClientTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let store: InMemoryTokenStore
    private let oauth = FakeOAuth()
    private let session: GitHubSession

    init() {
        let now = now
        store = InMemoryTokenStore(tokens: .sample(accessTokenExpiresAt: now.addingTimeInterval(3600)))
        session = GitHubSession(store: store, oauth: oauth, now: { now })
    }

    private func client(_ respond: @escaping (URLRequest) throws -> (Int, String)) -> (GitHubAPIClient, StubTransport) {
        let transport = StubTransport(respond: respond)
        return (GitHubAPIClient(transport: transport, session: session), transport)
    }

    @Test func currentUserLoginSendsTheAccessTokenAndReturnsTheLogin() async throws {
        let (client, transport) = client { _ in (200, #"{"login":"octocat","id":1}"#) }

        #expect(try await client.currentUserLogin() == "octocat")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/user")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-old")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }

    @Test func installedRepositoriesCollectsEveryInstallationSortedByFullName() async throws {
        let (client, _) = client { request in
            switch request.url!.path {
            case "/user/installations":
                (200, #"{"total_count":2,"installations":[{"id":11},{"id":22}]}"#)
            case "/user/installations/11/repositories":
                (200, #"{"total_count":1,"repositories":[{"name":"notes","owner":{"login":"octocat"}}]}"#)
            case "/user/installations/22/repositories":
                (200, #"{"total_count":2,"repositories":[{"name":"journal","owner":{"login":"acme"}},{"name":"diary","owner":{"login":"acme"}}]}"#)
            default:
                (404, "{}")
            }
        }

        #expect(try await client.installedRepositories() == [
            Repository(owner: "acme", name: "diary"),
            Repository(owner: "acme", name: "journal"),
            Repository(owner: "octocat", name: "notes"),
        ])
    }

    @Test func installedRepositoriesIsEmptyWhenTheAppIsNotInstalled() async throws {
        let (client, transport) = client { _ in (200, #"{"total_count":0,"installations":[]}"#) }

        #expect(try await client.installedRepositories().isEmpty)
        #expect(transport.requests.count == 1)
    }

    @Test func installedRepositoriesFollowsPagesUntilTheTotalCountIsReached() async throws {
        let (client, transport) = client { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            let page = query.first { $0.name == "page" }?.value
            switch (request.url!.path, page) {
            case ("/user/installations", _):
                return (200, #"{"total_count":1,"installations":[{"id":11}]}"#)
            case (_, "1"):
                return (200, #"{"total_count":2,"repositories":[{"name":"a","owner":{"login":"octocat"}}]}"#)
            default:
                return (200, #"{"total_count":2,"repositories":[{"name":"b","owner":{"login":"octocat"}}]}"#)
            }
        }

        #expect(try await client.installedRepositories().map(\.name) == ["a", "b"])
        #expect(transport.requests.map { $0.url!.query() } == ["per_page=100&page=1", "per_page=100&page=1", "per_page=100&page=2"])
    }

    @Test func aRefusedAccessTokenIsRefreshedAndTheRequestRetriedOnce() async throws {
        let (client, transport) = client { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer access-new"
                ? (200, #"{"login":"octocat"}"#)
                : (401, #"{"message":"Bad credentials"}"#)
        }

        #expect(try await client.currentUserLogin() == "octocat")
        #expect(transport.requests.count == 2)
    }

    @Test func aRefusedAccessTokenEndsTheSessionWhenTheRefreshIsRejectedToo() async {
        oauth.refreshResult = .failure(OAuthError.rejected("bad_refresh_token"))
        let (client, _) = client { _ in (401, #"{"message":"Bad credentials"}"#) }

        await #expect(throws: SessionError.signedOut) {
            try await client.currentUserLogin()
        }
        #expect(store.tokens == nil)
    }

    @Test func aTokenRefusedAgainAfterTheRefreshIsReportedWithoutAThirdRequest() async {
        let (client, transport) = client { _ in (401, #"{"message":"Bad credentials"}"#) }

        await #expect(throws: GitHubAPIError.unexpectedStatus(401)) {
            try await client.currentUserLogin()
        }
        #expect(transport.requests.count == 2)
    }

    @Test func aServerErrorIsReportedAndKeepsTheSession() async {
        let (client, _) = client { _ in (503, "{}") }

        await #expect(throws: GitHubAPIError.unexpectedStatus(503)) {
            try await client.currentUserLogin()
        }
        #expect(store.tokens != nil)
    }

    @Test func creatingAFilePutsTheBase64ContentAndMessageAtThePath() async throws {
        let (client, transport) = client { _ in (201, #"{"content":{}}"#) }

        try await client.createFile(
            at: "notes/2026/10/2026-10-03T135812Z-a1b2.md",
            in: Repository(owner: "octocat", name: "notes"),
            content: Data("Hello\n".utf8),
            message: "Add note"
        )

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octocat/notes/contents/notes/2026/10/2026-10-03T135812Z-a1b2.md")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-old")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["message": "Add note", "content": "SGVsbG8K"])
    }

    @Test(arguments: [404, 403, 409])
    func creatingAFileReportsTheStatusGitHubRefusedItWith(status: Int) async {
        let (client, _) = client { _ in (status, #"{"message":"refused"}"#) }

        await #expect(throws: GitHubAPIError.unexpectedStatus(status)) {
            try await client.createFile(at: "notes/a.md", in: Repository(owner: "octocat", name: "notes"), content: Data(), message: "Add note")
        }
    }

    private func clientAnswering422(existingFile: (Int, String)) -> GitHubAPIClient {
        client { request in
            request.httpMethod == "PUT" ? (422, #"{"message":"Invalid request.\n\n\"sha\" wasn't supplied."}"#) : existingFile
        }.0
    }

    @Test func creatingAFileSucceedsWhenThePathAlreadyHoldsTheSameContent() async throws {
        // GitHub wraps the base64 content of a file in lines.
        let client = clientAnswering422(existingFile: (200, #"{"content":"SGVs\nbG8K\n","encoding":"base64"}"#))

        try await client.createFile(at: "notes/a.md", in: Repository(owner: "octocat", name: "notes"), content: Data("Hello\n".utf8), message: "Add note")
    }

    @Test func creatingAFileThrowsFileAlreadyExistsWhenThePathHoldsDifferentContent() async {
        let client = clientAnswering422(existingFile: (200, #"{"content":"T3RoZXIK\n","encoding":"base64"}"#))

        await #expect(throws: GitHubAPIError.fileAlreadyExists) {
            try await client.createFile(at: "notes/a.md", in: Repository(owner: "octocat", name: "notes"), content: Data("Hello\n".utf8), message: "Add note")
        }
    }

    @Test func creatingAFileReportsThe422WhenNoFileIsAtThePath() async {
        let client = clientAnswering422(existingFile: (404, #"{"message":"Not Found"}"#))

        await #expect(throws: GitHubAPIError.unexpectedStatus(422)) {
            try await client.createFile(at: "notes/a.md", in: Repository(owner: "octocat", name: "notes"), content: Data("Hello\n".utf8), message: "Add note")
        }
    }

    @Test func creatingAFileReportsTheFailureOfTheReadBackWhenItIsNotAMissingFile() async {
        let client = clientAnswering422(existingFile: (503, "{}"))

        await #expect(throws: GitHubAPIError.unexpectedStatus(503)) {
            try await client.createFile(at: "notes/a.md", in: Repository(owner: "octocat", name: "notes"), content: Data("Hello\n".utf8), message: "Add note")
        }
    }
}
