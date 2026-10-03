import Foundation

struct DeviceCode: Equatable, Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let interval: Int

    private enum CodingKeys: String, CodingKey {
        case deviceCode, userCode, verificationURL = "verificationUri", interval
    }
}

struct TokenGrant: Equatable, Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String
}

enum DeviceTokenPoll: Equatable {
    case authorized(TokenGrant)
    case pending
    case slowDown(interval: Int?)
}

enum OAuthError: Error, Equatable {
    case expiredCode
    case accessDenied
    /// GitHub answered with an OAuth error code. Retrying the same request will not succeed.
    case rejected(String)
    case invalidResponse
}

protocol GitHubOAuth {
    func requestDeviceCode() async throws -> DeviceCode
    func pollToken(deviceCode: String) async throws -> DeviceTokenPoll
    func refresh(refreshToken: String) async throws -> TokenGrant
}

struct GitHubOAuthClient: GitHubOAuth {
    let clientID: String
    let transport: HTTPTransport

    func requestDeviceCode() async throws -> DeviceCode {
        try await post("https://github.com/login/device/code", form: ["client_id": clientID]).success()
    }

    func pollToken(deviceCode: String) async throws -> DeviceTokenPoll {
        let response = try await post(Self.tokenEndpoint, form: [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        switch response.failure?.error {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown(interval: response.failure?.interval)
        case "expired_token":
            throw OAuthError.expiredCode
        case "access_denied":
            throw OAuthError.accessDenied
        default:
            return .authorized(try response.success())
        }
    }

    func refresh(refreshToken: String) async throws -> TokenGrant {
        try await post(Self.tokenEndpoint, form: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]).success()
    }

    private static let tokenEndpoint = "https://github.com/login/oauth/access_token"

    private func post(_ endpoint: String, form: [String: String]) async throws -> Response {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery.map { Data($0.utf8) }

        // GitHub reports OAuth errors such as authorization_pending with status 200,
        // so the body is the only place to tell them apart and the status is not checked.
        let (data, _) = try await transport.send(request)
        return Response(data: data, failure: try? JSONDecoder.gitHub.decode(Failure.self, from: data))
    }

    private struct Failure: Decodable {
        let error: String
        let interval: Int?
    }

    private struct Response {
        let data: Data
        let failure: Failure?

        func success<Success: Decodable>() throws -> Success {
            if let failure {
                throw OAuthError.rejected(failure.error)
            }
            guard let success = try? JSONDecoder.gitHub.decode(Success.self, from: data) else {
                throw OAuthError.invalidResponse
            }
            return success
        }
    }
}
