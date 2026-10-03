import Foundation
import Security

struct TokenSet: Codable, Equatable {
    var accessToken: String
    var accessTokenExpiresAt: Date
    var refreshToken: String
}

extension TokenSet {
    init(_ grant: TokenGrant, receivedAt now: Date) {
        self.init(
            accessToken: grant.accessToken,
            accessTokenExpiresAt: now.addingTimeInterval(TimeInterval(grant.expiresIn)),
            refreshToken: grant.refreshToken
        )
    }
}

protocol TokenStore {
    func load() throws -> TokenSet?
    func save(_ tokens: TokenSet) throws
    func delete() throws
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

struct KeychainTokenStore: TokenStore {
    var service = "com.yamat47.Nageire.github"
    var account = "user-tokens"

    func load() throws -> TokenSet? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(TokenSet.self, from: data)
    }

    func save(_ tokens: TokenSet) throws {
        let data = try JSONEncoder().encode(tokens)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        // A refresh token is single-use, so a copy restored on another device would be
        // invalidated by the first refresh on either one. ThisDeviceOnly keeps the item
        // out of iCloud Keychain and device-to-device migration. AfterFirstUnlock rather
        // than WhenUnlocked because background sync will read it while the device is locked.
        //
        // TODO: Move the macOS build to the data protection keychain once it is signed with a provisioning profile.
        // macOS puts this item in the file-based login keychain, which ignores the accessibility
        // class and is copied by Migration Assistant. kSecUseDataProtectionKeychain selects the
        // keychain iOS uses, but fails with errSecMissingEntitlement in a build that carries no
        // application identifier entitlement, which is every build until distribution is set up.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
