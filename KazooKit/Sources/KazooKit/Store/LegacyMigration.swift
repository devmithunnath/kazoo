import Foundation
import Security

/// One-time move of data saved while the app was called "KazooBar" (bundle ID com.pipboxes.kazoobar).
/// Runs once per Mac; afterwards the legacy locations are left empty.
public enum LegacyMigration {
    static let legacyDomain = "com.pipboxes.kazoobar"
    static let legacyPreferencesKey = "KazooBar.preferences.v1"
    static let legacyKeychainService = "com.pipboxes.kazoobar.credentials"
    static let legacySupportFolder = "KazooBar"
    static let doneKey = "Kazoo.migratedFromKazooBar"

    public static func runIfNeeded(defaults: UserDefaults = .standard, secrets: any SecretStoring) {
        guard !defaults.bool(forKey: self.doneKey) else { return }
        defer { defaults.set(true, forKey: self.doneKey) }

        // Preferences (accounts, favorite, pins). Never overwrite preferences saved under the new name.
        if defaults.data(forKey: UserDefaultsPreferences.key) == nil,
           let legacy = UserDefaults(suiteName: self.legacyDomain),
           let data = legacy.data(forKey: self.legacyPreferencesKey),
           var prefs = try? JSONDecoder().decode(AppPreferences.self, from: data)
        {
            if prefs.displayName == "KazooBar" { prefs.displayName = "Kazoo" }
            UserDefaultsPreferences(defaults: defaults).save(prefs)
            legacy.removeObject(forKey: self.legacyPreferencesKey)
        }

        // Keychain secrets: only providers that actually have a legacy item are touched.
        for provider in ProviderID.allCases where secrets.secret(for: provider) == nil {
            guard let value = self.legacySecret(provider) else { continue }
            try? secrets.setSecret(value, for: provider)
            self.deleteLegacySecret(provider)
        }

        // Cached readings.
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = base.appendingPathComponent(self.legacySupportFolder, isDirectory: true)
            let new = base.appendingPathComponent("Kazoo", isDirectory: true)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
            }
        }
    }

    private static func legacyQuery(_ provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.legacyKeychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    private static func legacySecret(_ provider: ProviderID) -> String? {
        var query = self.legacyQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacySecret(_ provider: ProviderID) {
        SecItemDelete(self.legacyQuery(provider) as CFDictionary)
    }
}
