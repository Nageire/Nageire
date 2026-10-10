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

    private let rootTree = """
        {"sha":"r","truncated":false,"tree":[
          {"path":"README.md","type":"blob","sha":"s0"},
          {"path":"notes","type":"tree","sha":"n1"},
          {"path":"photos","type":"tree","sha":"p1"}
        ]}
        """

    @Test func noteFilesListsTheNotesAndTheirFilesWithTheirFullPaths() async throws {
        let rootTree = rootTree
        let (client, transport) = client { request in
            guard request.url!.path.hasSuffix("/git/trees/n1") else { return (200, rootTree) }
            return (200, """
                {"sha":"n1","truncated":false,"tree":[
                  {"path":"2026","type":"tree","sha":"s1"},
                  {"path":"2026/10","type":"tree","sha":"s2"},
                  {"path":"2026/10/2026-10-03T135812Z-a1b2.md","type":"blob","sha":"s3"},
                  {"path":"2026/10/photo.png","type":"blob","sha":"s4"},
                  {"path":"2026/11/2026-11-01T090000Z-07de.md","type":"blob","sha":"s5"}
                ]}
                """)
        }

        let files = try await client.noteFiles(in: Repository(owner: "octocat", name: "notes"))

        #expect(files == [
            RemoteFile(path: "notes/2026/10/2026-10-03T135812Z-a1b2.md", sha: "s3"),
            RemoteFile(path: "notes/2026/10/photo.png", sha: "s4"),
            RemoteFile(path: "notes/2026/11/2026-11-01T090000Z-07de.md", sha: "s5"),
        ])
        #expect(transport.requests.map { $0.url!.absoluteString } == [
            "https://api.github.com/repos/octocat/notes/git/trees/HEAD",
            "https://api.github.com/repos/octocat/notes/git/trees/n1?recursive=1",
        ])
    }

    @Test func noteFilesIsEmptyForARepositoryWithoutANotesDirectory() async throws {
        let (client, transport) = client { _ in (200, #"{"sha":"r","truncated":false,"tree":[{"path":"README.md","type":"blob","sha":"s0"}]}"#) }

        #expect(try await client.noteFiles(in: Repository(owner: "octocat", name: "notes")).isEmpty)
        #expect(transport.requests.count == 1)
    }

    @Test func noteFilesIsEmptyForARepositoryWithoutCommits() async throws {
        let (client, _) = client { _ in (409, #"{"message":"Git Repository is empty."}"#) }

        #expect(try await client.noteFiles(in: Repository(owner: "octocat", name: "notes")).isEmpty)
    }

    @Test func noteFilesFailsForARepositoryTheAppCannotReachInsteadOfListingNothing() async {
        let (client, _) = client { _ in (404, #"{"message":"Not Found"}"#) }

        await #expect(throws: GitHubAPIError.unexpectedStatus(404)) {
            try await client.noteFiles(in: Repository(owner: "octocat", name: "notes"))
        }
    }

    @Test func noteFilesFailsWhenGitHubCutTheNotesListingShort() async {
        let rootTree = rootTree
        let (client, _) = client { request in
            request.url!.path.hasSuffix("/git/trees/n1") ? (200, #"{"sha":"n1","truncated":true,"tree":[]}"#) : (200, rootTree)
        }

        await #expect(throws: GitHubAPIError.invalidResponse) {
            try await client.noteFiles(in: Repository(owner: "octocat", name: "notes"))
        }
    }

    @Test func noteFilesReportsAServerError() async {
        let (client, _) = client { _ in (503, "{}") }

        await #expect(throws: GitHubAPIError.unexpectedStatus(503)) {
            try await client.noteFiles(in: Repository(owner: "octocat", name: "notes"))
        }
    }

    @Test func blobReturnsTheDecodedContentOfTheFile() async throws {
        let (client, transport) = client { _ in (200, #"{"sha":"s3","content":"SGVs\nbG8K\n","encoding":"base64"}"#) }

        let data = try await client.blob("s3", in: Repository(owner: "octocat", name: "notes"))

        #expect(String(decoding: data, as: UTF8.self) == "Hello\n")
        #expect(transport.requests.first?.url?.absoluteString == "https://api.github.com/repos/octocat/notes/git/blobs/s3")
    }
    private let notes = Repository(owner: "octocat", name: "notes")

    @Test func writingAFilePutsTheContentOverWhatThePathHolds() async throws {
        let (client, transport) = client { request in
            request.httpMethod == "GET" ? (200, #"{"sha":"0123abcd","content":"T2xkCg==\n"}"#) : (200, #"{"content":{}}"#)
        }

        try await client.writeFile(at: "notes/a.md", in: notes, content: Data("Hello\n".utf8), message: "Update a.md")

        #expect(transport.requests.map(\.httpMethod) == ["GET", "PUT"])
        let request = try #require(transport.requests.last)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octocat/notes/contents/notes/a.md")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["message": "Update a.md", "content": "SGVsbG8K", "sha": "0123abcd"])
    }

    @Test func writingAFileCreatesItWhenThePathHoldsNone() async throws {
        let (client, transport) = client { request in
            request.httpMethod == "GET" ? (404, #"{"message":"Not Found"}"#) : (201, #"{"content":{}}"#)
        }

        try await client.writeFile(at: "notes/a.md", in: notes, content: Data("Hello\n".utf8), message: "Update a.md")

        let body = try JSONDecoder().decode([String: String].self, from: try #require(transport.requests.last?.httpBody))
        #expect(body == ["message": "Update a.md", "content": "SGVsbG8K"])
    }

    @Test func writingAFileCommitsNothingWhenThePathAlreadyHoldsTheSameContent() async throws {
        let sha = RemoteFile.sha(of: Data("Hello\n".utf8))
        let (client, transport) = client { _ in (200, #"{"sha":"\#(sha)"}"#) }

        try await client.writeFile(at: "notes/a.md", in: notes, content: Data("Hello\n".utf8), message: "Update a.md")

        #expect(transport.requests.map(\.httpMethod) == ["GET"])
    }

    @Test(arguments: [403, 409])
    func writingAFileReportsTheStatusGitHubRefusedItWith(status: Int) async {
        let (client, _) = client { request in
            request.httpMethod == "GET" ? (200, #"{"sha":"0123abcd"}"#) : (status, #"{"message":"refused"}"#)
        }

        await #expect(throws: GitHubAPIError.unexpectedStatus(status)) {
            try await client.writeFile(at: "notes/a.md", in: notes, content: Data("Hello\n".utf8), message: "Update a.md")
        }
    }

    @Test func deletingAFileSendsTheIdentifierOfWhatThePathHolds() async throws {
        let (client, transport) = client { _ in (200, #"{"sha":"0123abcd"}"#) }

        try await client.deleteFile(at: "notes/a.md", in: notes, message: "Delete a.md")

        #expect(transport.requests.map(\.httpMethod) == ["GET", "DELETE"])
        let request = try #require(transport.requests.last)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octocat/notes/contents/notes/a.md")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["message": "Delete a.md", "sha": "0123abcd"])
    }

    @Test func deletingAFileSucceedsWithoutACommitWhenTheRepositoryHoldsNoSuchFile() async throws {
        let (client, transport) = client { request in
            request.url?.path == "/repos/octocat/notes" ? (200, "{}") : (404, #"{"message":"Not Found"}"#)
        }

        try await client.deleteFile(at: "notes/a.md", in: notes, message: "Delete a.md")

        #expect(transport.requests.map(\.httpMethod) == ["GET", "GET"])
    }

    @Test func deletingAFileFailsForARepositoryTheAppCannotReachInsteadOfTakingTheFileForGone() async {
        let (client, _) = client { _ in (404, #"{"message":"Not Found"}"#) }

        await #expect(throws: GitHubAPIError.unexpectedStatus(404)) {
            try await client.deleteFile(at: "notes/a.md", in: notes, message: "Delete a.md")
        }
    }

    @Test(arguments: [404, 409])
    func deletingAFileReportsTheStatusGitHubRefusedItWith(status: Int) async {
        let (client, _) = client { request in
            request.httpMethod == "GET" ? (200, #"{"sha":"0123abcd"}"#) : (status, #"{"message":"refused"}"#)
        }

        await #expect(throws: GitHubAPIError.unexpectedStatus(status)) {
            try await client.deleteFile(at: "notes/a.md", in: notes, message: "Delete a.md")
        }
    }
}
