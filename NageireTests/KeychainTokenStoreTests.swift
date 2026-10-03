import Foundation
import Testing
@testable import Nageire

@MainActor
struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(service: "NageireTests-\(UUID().uuidString)")
    private let tokens = TokenSet.sample(accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func savedTokensAreLoadedBackUntilTheyAreDeleted() throws {
        defer { try? store.delete() }
        #expect(try store.load() == nil)

        try store.save(tokens)
        #expect(try store.load() == tokens)

        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test func savingAgainReplacesTheStoredTokens() throws {
        defer { try? store.delete() }
        var renewed = tokens
        renewed.accessToken = "access-renewed"

        try store.save(tokens)
        try store.save(renewed)

        #expect(try store.load() == renewed)
    }

    @Test func deletingWhenNothingIsStoredSucceeds() throws {
        try store.delete()
    }
}
