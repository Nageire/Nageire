import Foundation
import Testing
@testable import Nageire

@MainActor
struct GitHubOAuthClientTests {
    private func client(answering body: String) -> (GitHubOAuthClient, StubTransport) {
        let transport = StubTransport { _ in (200, body) }
        return (GitHubOAuthClient(clientID: "client-id", transport: transport), transport)
    }

    @Test func requestingADeviceCodeSendsTheClientIDAndReturnsTheCode() async throws {
        let (client, transport) = client(answering: """
            {"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
            """)

        let code = try await client.requestDeviceCode()

        #expect(code == DeviceCode(deviceCode: "dc", userCode: "WDJB-MJHT", verificationURL: URL(string: "https://github.com/login/device")!, interval: 5))
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://github.com/login/device/code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.formBody == ["client_id": "client-id"])
    }

    @Test func requestingADeviceCodeThrowsRejectedWhenDeviceFlowIsDisabled() async {
        let (client, _) = client(answering: #"{"error":"device_flow_disabled"}"#)

        await #expect(throws: OAuthError.rejected("device_flow_disabled")) {
            try await client.requestDeviceCode()
        }
    }

    @Test func pollingSendsTheDeviceCodeGrantAndReturnsTheTokensOnceAuthorized() async throws {
        let (client, transport) = client(answering: """
            {"access_token":"at","expires_in":28800,"refresh_token":"rt","refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}
            """)

        let poll = try await client.pollToken(deviceCode: "dc")

        #expect(poll == .authorized(TokenGrant(accessToken: "at", expiresIn: 28800, refreshToken: "rt")))
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(request.formBody == [
            "client_id": "client-id",
            "device_code": "dc",
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
    }

    @Test func pollingReturnsPendingWhileTheUserHasNotAuthorized() async throws {
        let (client, _) = client(answering: #"{"error":"authorization_pending"}"#)

        #expect(try await client.pollToken(deviceCode: "dc") == .pending)
    }

    @Test func pollingReturnsSlowDownWithTheIntervalGitHubAsksFor() async throws {
        let (client, _) = client(answering: #"{"error":"slow_down","interval":10}"#)

        #expect(try await client.pollToken(deviceCode: "dc") == .slowDown(interval: 10))
    }

    @Test(arguments: [
        ("expired_token", OAuthError.expiredCode),
        ("access_denied", OAuthError.accessDenied),
        ("incorrect_device_code", OAuthError.rejected("incorrect_device_code")),
    ])
    func pollingThrowsForATerminalError(code: String, expected: OAuthError) async {
        let (client, _) = client(answering: #"{"error":"\#(code)"}"#)

        await #expect(throws: expected) {
            try await client.pollToken(deviceCode: "dc")
        }
    }

    @Test func pollingThrowsInvalidResponseWhenTheTokensCarryNoRefreshToken() async {
        let (client, _) = client(answering: #"{"access_token":"at","expires_in":28800,"token_type":"bearer"}"#)

        await #expect(throws: OAuthError.invalidResponse) {
            try await client.pollToken(deviceCode: "dc")
        }
    }

    @Test func refreshingSendsTheRefreshTokenWithoutAClientSecretAndReturnsNewTokens() async throws {
        let (client, transport) = client(answering: """
            {"access_token":"at2","expires_in":28800,"refresh_token":"rt2","refresh_token_expires_in":15897600}
            """)

        let grant = try await client.refresh(refreshToken: "rt")

        #expect(grant == TokenGrant(accessToken: "at2", expiresIn: 28800, refreshToken: "rt2"))
        #expect(transport.requests.first?.formBody == [
            "client_id": "client-id",
            "grant_type": "refresh_token",
            "refresh_token": "rt",
        ])
    }

    @Test func refreshingThrowsRejectedWhenTheRefreshTokenIsNoLongerValid() async {
        let (client, _) = client(answering: #"{"error":"bad_refresh_token"}"#)

        await #expect(throws: OAuthError.rejected("bad_refresh_token")) {
            try await client.refresh(refreshToken: "rt")
        }
    }

    @Test func aBodyThatIsNotJSONThrowsInvalidResponse() async {
        let transport = StubTransport { _ in (502, "<html>Bad Gateway</html>") }
        let client = GitHubOAuthClient(clientID: "client-id", transport: transport)

        await #expect(throws: OAuthError.invalidResponse) {
            try await client.refresh(refreshToken: "rt")
        }
    }
}
