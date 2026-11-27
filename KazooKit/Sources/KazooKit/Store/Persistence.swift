import Foundation

/// Ordinary preferences (no secrets). Backed by UserDefaults.
public struct AppPreferences: Codable, Sendable, Equatable {
    /// Connected accounts in connection order. Order is stable across refreshes.
    public var accounts: [ConnectedAccount] = []
    public var favorite: ProviderID?
    /// Up to three pinned providers for the overview, in the user's order.
    public var pinned: [ProviderID] = []
    public var demoMode: Bool = false
    public var showMenuBarItemAlways: Bool = false
    public var refreshIntervalMinutes: Int = 5
    public var displayName: String = "Kazoo"

    public init() {}

    public static let maxPinned = 3
}

public protocol PreferencesPersisting: Sendable {
    func load() -> AppPreferences
    func save(_ preferences: AppPreferences)
}

public struct UserDefaultsPreferences: PreferencesPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    static let key = "Kazoo.preferences.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> AppPreferences {
        guard let data = self.defaults.data(forKey: Self.key),
              let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) else { return AppPreferences() }
        return prefs
    }

    public func save(_ preferences: AppPreferences) {
        if let data = try? JSONEncoder().encode(preferences) { self.defaults.set(data, forKey: Self.key) }
    }
}

public final class MemoryPreferences: PreferencesPersisting, @unchecked Sendable {
    private var value: AppPreferences
    public init(_ value: AppPreferences = AppPreferences()) { self.value = value }
    public func load() -> AppPreferences { self.value }
    public func save(_ preferences: AppPreferences) { self.value = preferences }
}

/// Last successful reading per provider, so a relaunch or a transient failure still shows data with its age.
public protocol ReadingCaching: Sendable {
    func load() -> [ProviderID: UsageReading]
    func save(_ readings: [ProviderID: UsageReading])
}

public struct FileReadingCache: ReadingCaching {
    public let url: URL
    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.url = base.appendingPathComponent("Kazoo", isDirectory: true)
                .appendingPathComponent("readings.json")
        }
    }

    public func load() -> [ProviderID: UsageReading] {
        guard let data = try? Data(contentsOf: self.url),
              let list = try? JSONDecoder().decode([UsageReading].self, from: data) else { return [:] }
        return Dictionary(list.filter { !$0.isDemo }.map { ($0.provider, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func save(_ readings: [ProviderID: UsageReading]) {
        let list = readings.values.filter { !$0.isDemo }
        try? FileManager.default.createDirectory(
            at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(list)) {
            try? data.write(to: self.url, options: [.atomic, .completeFileProtection])
        }
    }
}

public final class MemoryReadingCache: ReadingCaching, @unchecked Sendable {
    private var value: [ProviderID: UsageReading] = [:]
    public init() {}
    public func load() -> [ProviderID: UsageReading] { self.value }
    public func save(_ readings: [ProviderID: UsageReading]) { self.value = readings }
}
