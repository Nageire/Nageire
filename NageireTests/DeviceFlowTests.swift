import Foundation
import Testing
@testable import Nageire

@MainActor
struct DeviceFlowTests {
    private let oauth = FakeOAuth()

    private final class SleepLog {
        var durations: [Duration] = []
    }

    private func flow(recordingInto log: SleepLog) -> DeviceFlow {
        DeviceFlow(oauth: oauth, sleep: { log.durations.append($0) })
    }

    @Test func waitsForTheIntervalBeforeEveryPollUntilAuthorized() async throws {
        oauth.polls = [.success(.pending), .success(.pending), .success(.authorized(.sample))]
        let log = SleepLog()

        let grant = try await flow(recordingInto: log).waitForAuthorization(of: .sample)

        #expect(grant == .sample)
        #expect(log.durations == [.seconds(5), .seconds(5), .seconds(5)])
    }

    @Test func slowDownSwitchesToTheIntervalInTheResponse() async throws {
        oauth.polls = [.success(.slowDown(interval: 12)), .success(.pending), .success(.authorized(.sample))]
        let log = SleepLog()

        _ = try await flow(recordingInto: log).waitForAuthorization(of: .sample)

        #expect(log.durations == [.seconds(5), .seconds(12), .seconds(12)])
    }

    @Test func slowDownWithoutAnIntervalAddsFiveSeconds() async throws {
        oauth.polls = [.success(.slowDown(interval: nil)), .success(.slowDown(interval: nil)), .success(.authorized(.sample))]
        let log = SleepLog()

        _ = try await flow(recordingInto: log).waitForAuthorization(of: .sample)

        #expect(log.durations == [.seconds(5), .seconds(10), .seconds(15)])
    }

    @Test func aNetworkFailureOnOnePollKeepsWaitingForTheSameCode() async throws {
        oauth.polls = [.failure(URLError(.networkConnectionLost)), .success(.authorized(.sample))]
        let log = SleepLog()

        let grant = try await flow(recordingInto: log).waitForAuthorization(of: .sample)

        #expect(grant == .sample)
        #expect(log.durations == [.seconds(5), .seconds(5)])
    }

    @Test func anExpiredCodeStopsPolling() async {
        oauth.polls = [.success(.pending), .failure(OAuthError.expiredCode), .success(.authorized(.sample))]
        let log = SleepLog()

        await #expect(throws: OAuthError.expiredCode) {
            try await flow(recordingInto: log).waitForAuthorization(of: .sample)
        }
        #expect(oauth.polls.count == 1)
    }

    @Test func cancellationDuringTheWaitStopsPollingWithoutAskingGitHub() async {
        oauth.polls = [.success(.authorized(.sample))]
        let flow = DeviceFlow(oauth: oauth, sleep: { _ in throw CancellationError() })

        await #expect(throws: CancellationError.self) {
            try await flow.waitForAuthorization(of: .sample)
        }
        #expect(oauth.polls.count == 1)
    }
}
