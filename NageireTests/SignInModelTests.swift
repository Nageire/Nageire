import Foundation
import Testing
@testable import Nageire

@MainActor
struct SignInModelTests {
    private let oauth = FakeOAuth()

    private final class Received {
        var grants: [TokenGrant] = []
    }

    private func model(received: Received = Received(), sleep: @escaping (Duration) async throws -> Void = { _ in }) -> SignInModel {
        SignInModel(flow: DeviceFlow(oauth: oauth, sleep: sleep)) { received.grants.append($0) }
    }

    @Test func showsTheUserCodeWhileWaitingAndHandsOverTheTokensOnceAuthorized() async {
        oauth.polls = [.success(.pending), .success(.authorized(.sample))]
        let received = Received()
        var statesWhileWaiting: [SignInModel.State] = []
        var model: SignInModel!
        model = self.model(received: received) { _ in statesWhileWaiting.append(model.state) }

        await model.signIn()

        #expect(statesWhileWaiting == [.awaitingAuthorization(.sample), .awaitingAuthorization(.sample)])
        #expect(received.grants == [.sample])
    }

    @Test(arguments: [
        (OAuthError.expiredCode, SignInModel.Failure.expired),
        (OAuthError.accessDenied, SignInModel.Failure.denied),
        (OAuthError.rejected("incorrect_device_code"), SignInModel.Failure.other),
    ])
    func aTerminalPollErrorEndsInTheMatchingFailure(error: OAuthError, failure: SignInModel.Failure) async {
        oauth.polls = [.failure(error)]
        let model = model()

        await model.signIn()

        #expect(model.state == .failed(failure))
    }

    @Test func failingToReachGitHubEndsInANetworkFailure() async {
        oauth.deviceCode = .failure(URLError(.notConnectedToInternet))
        let model = model()

        await model.signIn()

        #expect(model.state == .failed(.network))
    }

    @Test func cancellingWhileWaitingReturnsToIdle() async {
        oauth.polls = [.success(.authorized(.sample))]
        let received = Received()
        let model = model(received: received) { _ in try await Task.sleep(for: .seconds(60)) }

        let task = Task { await model.signIn() }
        while model.state != .awaitingAuthorization(.sample) {
            await Task.yield()
        }
        task.cancel()
        await task.value

        #expect(model.state == .idle)
        #expect(received.grants.isEmpty)
    }
}
