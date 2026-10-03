import Foundation
import Observation

@Observable
final class SignInModel {
    enum State: Equatable {
        case idle
        case requestingCode
        case awaitingAuthorization(DeviceCode)
        case failed(Failure)
    }

    enum Failure: Equatable {
        case expired
        case denied
        case network
        case other
    }

    private(set) var state: State = .idle

    private let flow: DeviceFlow
    private let onAuthorized: (TokenGrant) throws -> Void

    init(flow: DeviceFlow, onAuthorized: @escaping (TokenGrant) throws -> Void) {
        self.flow = flow
        self.onAuthorized = onAuthorized
    }

    /// Runs the device flow from requesting a code to receiving the tokens. Cancelling the surrounding task returns to idle.
    func signIn() async {
        state = .requestingCode
        do {
            let code = try await flow.oauth.requestDeviceCode()
            state = .awaitingAuthorization(code)
            let grant = try await flow.waitForAuthorization(of: code)
            try onAuthorized(grant)
            state = .idle
        } catch {
            // URLSession reports cancellation as URLError.cancelled rather than CancellationError,
            // so the task's own flag is the one check that covers the wait and the requests.
            state = Task.isCancelled ? .idle : .failed(Failure(error))
        }
    }
}

private extension SignInModel.Failure {
    init(_ error: Error) {
        switch error {
        case OAuthError.expiredCode: self = .expired
        case OAuthError.accessDenied: self = .denied
        case is URLError: self = .network
        default: self = .other
        }
    }
}
