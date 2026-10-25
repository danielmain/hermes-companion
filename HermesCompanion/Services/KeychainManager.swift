import Foundation
import Security
import os

public enum KeychainError: LocalizedError, Equatable {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case encodingError

    public var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in Keychain."
        case .itemNotFound:
            return "Item not found in Keychain."
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .encodingError:
            return "Failed to encode/decode Keychain data."
        }
    }
}

public final class KeychainManager {
    public static let shared = KeychainManager()

    private let service = "dev.funktional.HermesCompanion.directToken"
    private let account = "bearer_token"
    private let logger = Logger(subsystem: "dev.funktional.HermesCompanion", category: "KeychainManager")

    private init() {}

    // MARK: - Direct Bearer Token Storage

    @discardableResult
    public func saveToken(_ token: String) -> Result<Void, KeychainError> {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleanToken.data(using: .utf8) else {
            return .failure(.encodingError)
        }

        // Delete any existing item first
        _ = deleteToken()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to save Bearer token to Keychain: \(status)")
            return .failure(.unexpectedStatus(status))
        }

        logger.info("Direct Connection Bearer token saved securely to Keychain")
        return .success(())
    }

    public func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    @discardableResult
    public func deleteToken() -> Result<Void, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return .success(())
        }
        return .failure(.unexpectedStatus(status))
    }
}
