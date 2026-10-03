import Foundation

struct DeviceFlow {
    let oauth: GitHubOAuth
    var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func waitForAuthorization(of code: DeviceCode) async throws -> TokenGrant {
        var interval = code.interval
        while true {
            try await sleep(.seconds(interval))
            let poll: DeviceTokenPoll
            do {
                poll = try await oauth.pollToken(deviceCode: code.deviceCode)
            } catch is URLError {
                // The user is in the browser entering the code while this runs, so the app is
                // in the background, where a request in flight is often cut off. The code is
                // still good, and giving up here would discard an authorization already made.
                continue
            }
            switch poll {
            case .authorized(let grant):
                return grant
            case .pending:
                continue
            case .slowDown(let newInterval):
                // RFC 8628 section 3.5 sets the increase at 5 seconds when the response names no interval.
                interval = newInterval ?? interval + 5
            }
        }
    }
}
