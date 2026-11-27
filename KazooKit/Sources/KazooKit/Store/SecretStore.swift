import Foundation
import Security

/// App-owned secrets (API keys, device-flow tokens). Keychain only; never logged or written to disk.
public protocol SecretStoring: Sendable {
    func secret(for provider: ProviderID) -> String?
    func setSecret(_ secret: String?, for provider: ProviderID) throws
}

public struct KeychainSecretStore: SecretStoring {
    public let service: String

    public init(service: String = "com.pipboxes.kazoo.credentials") {
        self.service = service
    }

    private func baseQuery(_ provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    public func secret(for provider: ProviderID) -> String? {
        var query = self.baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ secret: String?, for provider: ProviderID) throws {
        let query = self.baseQuery(provider)
        SecItemDelete(query as CFDictionary)
        guard let secret, !secret.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "Kazoo · \(provider.displayName)"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn’t save to Keychain (\(status))."])
        }
    }
}

/// In-memory store for tests and previews.
public final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    private var values: [ProviderID: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func secret(for provider: ProviderID) -> String? {
        self.lock.withLock { self.values[provider] }
    }
    public func setSecret(_ secret: String?, for provider: ProviderID) throws {
        self.lock.withLock { self.values[provider] = secret }
    }
}
