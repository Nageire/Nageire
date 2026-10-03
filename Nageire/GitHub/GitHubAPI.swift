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

enum GitHubAPIError: Error, Equatable {
    case unexpectedStatus(Int)
}

protocol GitHubAPI {
    func currentUserLogin() async throws -> String
    /// The repositories the signed-in user can reach through installations of the GitHub App, sorted by full name.
    func installedRepositories() async throws -> [Repository]
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
        var components = URLComponents(string: "https://api.github.com" + path)!
        if let page {
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ]
        }
        var request = URLRequest(url: components.url!)
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
        guard 200..<300 ~= response.statusCode else {
            throw GitHubAPIError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder.gitHub.decode(Response.self, from: data)
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
