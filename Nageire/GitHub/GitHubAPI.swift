import CryptoKit
import Foundation

struct Repository: Hashable, Identifiable {
    let owner: String
    let name: String

    var fullName: String { "\(owner)/\(name)" }
    var id: String { fullName }
}

extension Repository {
    init?(fullName: String) {
        let parts = fullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }
}

struct RemoteFile: Equatable {
    let path: String
    /// The Git blob identifier of the content.
    let sha: String

    /// The identifier Git gives a file's content. Computing it locally tells an unchanged file
    /// from a changed one without fetching it or keeping a separate index.
    static func sha(of contents: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(contents.count)\0".utf8))
        hasher.update(data: contents)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum GitHubAPIError: Error, Equatable {
    case unexpectedStatus(Int)
    /// The path holds a file with different content.
    case fileAlreadyExists
    /// A successful answer whose body is not what the endpoint documents.
    case invalidResponse
}

protocol GitHubAPI {
    func currentUserLogin() async throws -> String
    /// The repositories the signed-in user can reach through installations of the GitHub App, sorted by full name.
    func installedRepositories() async throws -> [Repository]
    /// Commits a new file to the default branch. Succeeds when the path already holds the same content,
    /// and throws `fileAlreadyExists` instead of overwriting different content.
    func createFile(at path: String, in repository: Repository, content: Data, message: String) async throws
    /// Every Markdown file under `notes/` on the default branch. Empty for a repository without commits.
    func noteFiles(in repository: Repository) async throws -> [RemoteFile]
    func blob(_ sha: String, in repository: Repository) async throws -> Data
}

struct GitHubAPIClient: GitHubAPI {
    let transport: HTTPTransport
    let session: GitHubSession

    func currentUserLogin() async throws -> String {
        let user: User = try await get("/user")
        return user.login
    }

    func installedRepositories() async throws -> [Repository] {
        let installations = try await allPages { page in
            let list: InstallationList = try await get("/user/installations", page: page)
            return (list.installations, list.totalCount)
        }
        var repositories: [Repository] = []
        for installation in installations {
            let items = try await allPages { page in
                let list: RepositoryList = try await get("/user/installations/\(installation.id)/repositories", page: page)
                return (list.repositories, list.totalCount)
            }
            repositories += items.map { Repository(owner: $0.owner.login, name: $0.name) }
        }
        return repositories.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }

    func createFile(at path: String, in repository: Repository, content: Data, message: String) async throws {
        let body = try JSONEncoder().encode(["message": message, "content": content.base64EncodedString()])
        let (_, status) = try await send("PUT", "/repos/\(repository.fullName)/contents/\(path)", body: body)
        guard status == 422 else {
            guard 200..<300 ~= status else {
                throw GitHubAPIError.unexpectedStatus(status)
            }
            return
        }
        // GitHub answers 422 both for a path that is taken and for an invalid request, and tells
        // them apart only in prose. Reading the path back settles it: the same content there means
        // an earlier attempt got through and only its response was lost.
        let existing: FileContent
        do {
            existing = try await get("/repos/\(repository.fullName)/contents/\(path)")
        } catch GitHubAPIError.unexpectedStatus(404) {
            throw GitHubAPIError.unexpectedStatus(status)
        }
        guard existing.data == content else {
            throw GitHubAPIError.fileAlreadyExists
        }
    }

    func noteFiles(in repository: Repository) async throws -> [RemoteFile] {
        let root: Tree
        do {
            root = try await get("/repos/\(repository.fullName)/git/trees/HEAD")
        } catch GitHubAPIError.unexpectedStatus(409) {
            // A repository without commits has no HEAD. A 404 is not treated the same way: it also
            // means a repository the app can no longer reach, and an empty answer would tell the
            // caller that every note was deleted.
            return []
        }
        guard let notes = root.tree.first(where: { $0.path == "notes" && $0.type == "tree" }) else {
            return []
        }
        // Only the notes directory is listed in full. GitHub cuts a recursive listing off past
        // 100,000 entries or 7 MB, and the repository may hold far more than notes.
        let tree: Tree = try await get("/repos/\(repository.fullName)/git/trees/\(notes.sha)?recursive=1")
        guard !tree.truncated else {
            // A partial listing would read as deletions.
            throw GitHubAPIError.invalidResponse
        }
        return tree.tree
            .filter { $0.type == "blob" && $0.path.hasSuffix(".md") }
            .map { RemoteFile(path: "notes/\($0.path)", sha: $0.sha) }
    }

    func blob(_ sha: String, in repository: Repository) async throws -> Data {
        let blob: FileContent = try await get("/repos/\(repository.fullName)/git/blobs/\(sha)")
        guard let data = blob.data else {
            throw GitHubAPIError.invalidResponse
        }
        return data
    }

    private func allPages<Item>(_ fetch: (Int) async throws -> (items: [Item], totalCount: Int)) async throws -> [Item] {
        var items: [Item] = []
        var page = 1
        while true {
            let result = try await fetch(page)
            items += result.items
            if result.items.isEmpty || items.count >= result.totalCount {
                return items
            }
            page += 1
        }
    }

    private func get<Response: Decodable>(_ path: String, page: Int? = nil) async throws -> Response {
        let (data, status) = try await send("GET", path, page: page)
        guard 200..<300 ~= status else {
            throw GitHubAPIError.unexpectedStatus(status)
        }
        return try JSONDecoder.gitHub.decode(Response.self, from: data)
    }

    private func send(_ method: String, _ path: String, page: Int? = nil, body: Data? = nil) async throws -> (Data, Int) {
        var components = URLComponents(string: "https://api.github.com" + path)!
        if let page {
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ]
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        var token = try await session.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await transport.send(request)
        if response.statusCode == 401 {
            // A device clock that runs behind makes an expired token look valid. One retry with a
            // refreshed token recovers from that, and the refresh itself ends the session when
            // the user has revoked the authorization.
            token = try await session.accessToken(replacing: token)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            (data, response) = try await transport.send(request)
        }
        return (data, response.statusCode)
    }

    private struct Tree: Decodable {
        let tree: [Entry]
        let truncated: Bool

        struct Entry: Decodable {
            let path: String
            let type: String
            let sha: String
        }
    }

    private struct FileContent: Decodable {
        let content: String

        /// GitHub wraps the base64 text in lines.
        var data: Data? { Data(base64Encoded: content, options: .ignoreUnknownCharacters) }
    }

    private struct User: Decodable {
        let login: String
    }

    private struct InstallationList: Decodable {
        let totalCount: Int
        let installations: [Installation]

        struct Installation: Decodable {
            let id: Int
        }
    }

    private struct RepositoryList: Decodable {
        let totalCount: Int
        let repositories: [Item]

        struct Item: Decodable {
            let name: String
            let owner: User
        }
    }
}
