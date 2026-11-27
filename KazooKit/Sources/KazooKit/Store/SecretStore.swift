import Darwin
import Foundation
import LocalAuthentication
import Security

/// Result of reading a saved secret without necessarily allowing a macOS prompt.
public enum SecretLookup: Sendable, Equatable {
    case found(String)
    case missing
    /// The item exists but macOS would have to ask the user first (e.g. after the app's signature changed).
    case needsPermission
}

/// App-owned secrets (API keys, device-flow tokens). Keychain only; never logged or written to disk.
public protocol SecretStoring: Sendable {
    /// Reads a secret, allowing a macOS Keychain prompt if one is needed (user actions only).
    func secret(for provider: ProviderID) -> String?
    /// Reads a secret; with `allowPrompt: false` it never shows UI and reports `.needsPermission` instead.
    func lookupSecret(for provider: ProviderID, allowPrompt: Bool) -> SecretLookup
    func setSecret(_ secret: String?, for provider: ProviderID) throws
}

extension SecretStoring {
    public func lookupSecret(for provider: ProviderID, allowPrompt _: Bool) -> SecretLookup {
        self.secret(for: provider).map(SecretLookup.found) ?? .missing
    }
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
        if case let .found(value) = self.lookupSecret(for: provider, allowPrompt: true) { return value }
        return nil
    }

    public func lookupSecret(for provider: ProviderID, allowPrompt: Bool) -> SecretLookup {
        var query = self.baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowPrompt { NoUIKeychainQuery.apply(to: &query) }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return .missing }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .needsPermission
        default:
            return .missing
        }
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

/// Keychain query options that fail instead of showing UI. Adapted from CodexBarCore's `KeychainNoUIQuery`
/// (MIT, © Peter Steinberger): `interactionNotAllowed` alone can still surface legacy Allow/Deny prompts, so the
/// legacy UI-fail policy is applied too, resolved at runtime to avoid the deprecated symbol at compile time.
enum NoUIKeychainQuery {
    private static let uiFailPolicy: String = {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else { return "u_AuthUIF" }
        let pointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (pointer.pointee as String?) ?? "u_AuthUIF"
    }()

    static func apply(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = self.uiFailPolicy as CFString
    }
}

/// In-memory store for tests and previews.
public final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    private var values: [ProviderID: String] = [:]
    private let lock = NSLock()
    /// Test hook: secrets that behave as if macOS would prompt before reading them.
    public var promptRequired: Set<ProviderID> = []
    public init() {}

    public func lookupSecret(for provider: ProviderID, allowPrompt: Bool) -> SecretLookup {
        self.lock.withLock {
            guard let value = self.values[provider] else { return .missing }
            if !allowPrompt, self.promptRequired.contains(provider) { return .needsPermission }
            return .found(value)
        }
    }
    public func secret(for provider: ProviderID) -> String? {
        self.lock.withLock { self.values[provider] }
    }
    public func setSecret(_ secret: String?, for provider: ProviderID) throws {
        self.lock.withLock { self.values[provider] = secret }
    }
}
