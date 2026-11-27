import AppKit
import Foundation

/// Checks GitHub for new Kazoo releases and installs them the way Kazoo was installed.
@MainActor
public final class UpdateController: ObservableObject {
    public enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing
        case updated(String)
        case failed(String)
        case updateFailed(String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var lastChecked: Date?
    @Published public var checksAutomatically: Bool {
        didSet { self.defaults.set(self.checksAutomatically, forKey: Keys.automatic) }
    }

    public let currentVersion: String
    public let buildNumber: String
    public let installMethod: InstallMethod
    private let fetcher: any ReleaseFetching
    private let defaults: UserDefaults
    private let clock: @Sendable () -> Date
    /// Called after the Homebrew helper starts; the app quits so the cask upgrade can replace it.
    public var quitForUpdate: () -> Void = { NSApp.terminate(nil) }
    public var startBrewUpdate: (String, String) throws -> Void = { try BrewUpdater.start(brewPath: $0, appPath: $1) }
    public var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Automatic checks run at most this often; manual checks always run.
    public static let automaticInterval: TimeInterval = 24 * 3600
    public static let minimumAutomaticInterval: TimeInterval = 6 * 3600

    enum Keys {
        static let automatic = "Kazoo.updates.automatic"
        static let lastChecked = "Kazoo.updates.lastChecked"
        static let pending = "Kazoo.updates.pending"
    }

    public init(
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
        installMethod: InstallMethod = .detect(),
        fetcher: (any ReleaseFetching)? = nil,
        defaults: UserDefaults = .standard,
        clock: @escaping @Sendable () -> Date = { Date() })
    {
        self.currentVersion = currentVersion
        self.buildNumber = buildNumber
        self.installMethod = installMethod
        self.fetcher = fetcher ?? GitHubReleaseFetcher(appVersion: currentVersion)
        self.defaults = defaults
        self.clock = clock
        self.checksAutomatically = defaults.object(forKey: Keys.automatic) as? Bool ?? true
        self.lastChecked = defaults.object(forKey: Keys.lastChecked) as? Date
        self.resolvePendingUpdate()
    }

    public var availableRelease: ReleaseInfo? {
        if case let .available(release) = self.status { return release }
        return nil
    }

    // MARK: Checking

    public func checkNow() {
        Task { await self.check() }
    }

    /// Runs an automatic check when enabled and due (daily, never more than every 6 hours).
    public func checkIfDue() {
        guard self.checksAutomatically, self.status != .checking, self.status != .installing else { return }
        if let last = self.lastChecked, self.clock().timeIntervalSince(last) < Self.automaticInterval { return }
        Task { await self.check(automatic: true) }
    }

    public func check(automatic: Bool = false) async {
        if automatic, let last = self.lastChecked,
           self.clock().timeIntervalSince(last) < Self.minimumAutomaticInterval
        {
            return
        }
        guard self.status != .checking, self.status != .installing else { return }
        let previous = self.status
        self.status = .checking
        do {
            let release = try await self.fetcher.latestRelease()
            self.lastChecked = self.clock()
            self.defaults.set(self.lastChecked, forKey: Keys.lastChecked)
            if let latest = AppVersion(release.version), let current = AppVersion(self.currentVersion), current < latest {
                self.status = .available(release)
            } else {
                self.status = .upToDate
            }
        } catch {
            // Automatic checks fail quietly; only a user's check reports the problem.
            self.status = automatic ? (previous == .checking ? .idle : previous) : .failed(error.errorDescription ?? "Update check failed.")
        }
    }

    // MARK: Installing

    public func install() {
        guard let release = self.availableRelease else { return }
        switch self.installMethod {
        case let .homebrew(brewPath):
            do {
                self.defaults.set(["from": self.currentVersion, "to": release.version,
                                   "started": self.clock().timeIntervalSince1970] as [String: Any],
                                  forKey: Keys.pending)
                try self.startBrewUpdate(brewPath, Bundle.main.bundleURL.path)
                self.status = .installing
                // Give the helper a moment to start before quitting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.quitForUpdate() }
            } catch {
                self.defaults.removeObject(forKey: Keys.pending)
                self.status = .updateFailed("Couldn’t start Homebrew: \(error.localizedDescription)")
            }
        case .manual, .development:
            self.openURL(release.downloadURL ?? release.pageURL)
        }
    }

    public func openReleaseNotes() {
        if let release = self.availableRelease { self.openURL(release.pageURL) }
    }

    public func copyManualCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BrewUpdater.manualCommand, forType: .string)
    }

    public func openUpdateLog() {
        self.openURL(BrewUpdater.logURL)
    }

    /// After a Homebrew update relaunches Kazoo, report whether it worked.
    private func resolvePendingUpdate() {
        guard let pending = self.defaults.dictionary(forKey: Keys.pending),
              let target = pending["to"] as? String else { return }
        self.defaults.removeObject(forKey: Keys.pending)
        if let started = pending["started"] as? TimeInterval,
           self.clock().timeIntervalSince1970 - started > 3600
        {
            return
        }
        if let current = AppVersion(self.currentVersion), let wanted = AppVersion(target), !(current < wanted) {
            self.status = .updated(self.currentVersion)
        } else {
            self.status = .updateFailed("Homebrew didn’t finish updating to \(target).")
        }
    }
}
