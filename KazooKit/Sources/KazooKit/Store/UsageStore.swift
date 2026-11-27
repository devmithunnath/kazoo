import Combine
import Foundation

/// The single source of truth for connected accounts, readings, and refresh state.
///
/// Refresh rules (adapted from CodexBar's refresh loop): one in-flight request per provider (duplicates join it),
/// exponential backoff on rate limits and transient failures, last good reading retained with its age, and a
/// per-provider generation counter so results from a disconnected or switched account are discarded.
@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var preferences: AppPreferences
    @Published public private(set) var liveReadings: [ProviderID: UsageReading]
    @Published public private(set) var demoReadings: [ProviderID: UsageReading] = [:]
    @Published public private(set) var statuses: [ProviderID: ConnectionStatus] = [:]
    @Published public private(set) var refreshing: Set<ProviderID> = []
    /// Ticks so countdowns and ages re-render.
    @Published public private(set) var now: Date

    public let liveSource: any UsageSource
    public let demoSource: any UsageSource
    public let secrets: any SecretStoring
    private let preferencesStore: any PreferencesPersisting
    private let cache: any ReadingCaching
    private let clock: @Sendable () -> Date

    private var inFlight: [ProviderID: Task<Void, Never>] = [:]
    private var generation: [ProviderID: Int] = [:]
    private var failureCount: [ProviderID: Int] = [:]
    private var backoffUntil: [ProviderID: Date] = [:]
    private var lastAttempt: [ProviderID: Date] = [:]
    /// Reset timestamps that already triggered a confirmation refresh, so a stale timestamp cannot loop.
    private var resetRefreshRequested: [ProviderID: Date] = [:]
    private var timer: Timer?

    public init(
        liveSource: any UsageSource,
        demoSource: any UsageSource = DemoUsageSource(),
        secrets: any SecretStoring,
        preferences: any PreferencesPersisting,
        cache: any ReadingCaching,
        clock: @escaping @Sendable () -> Date = { Date() })
    {
        self.liveSource = liveSource
        self.demoSource = demoSource
        self.secrets = secrets
        self.preferencesStore = preferences
        self.cache = cache
        self.clock = clock
        let prefs = preferences.load()
        self.preferences = prefs
        let connected = Set(prefs.accounts.map(\.provider))
        self.liveReadings = cache.load().filter { connected.contains($0.key) }
        self.now = clock()
        for account in prefs.accounts { self.statuses[account.provider] = .connected }
        if prefs.demoMode { self.demoReadings = Fixtures.allReadings(now: self.now) }
    }

    // MARK: - Derived state

    public var isDemo: Bool { self.preferences.demoMode }

    /// Connected providers in stable connection order.
    public var connectedProviders: [ProviderID] {
        self.isDemo ? ProviderID.allCases : self.preferences.accounts.map(\.provider)
    }

    public var hasConnections: Bool { !self.connectedProviders.isEmpty }

    public func reading(for provider: ProviderID) -> UsageReading? {
        self.isDemo ? self.demoReadings[provider] : self.liveReadings[provider]
    }

    public func status(for provider: ProviderID) -> ConnectionStatus {
        if self.isDemo { return .connected }
        return self.statuses[provider] ?? .notConnected
    }

    public func account(for provider: ProviderID) -> ConnectedAccount? {
        self.preferences.accounts.first { $0.provider == provider }
    }

    public func isConnected(_ provider: ProviderID) -> Bool {
        self.connectedProviders.contains(provider)
    }

    public var favoriteProvider: ProviderID? {
        let connected = self.connectedProviders
        if let favorite = self.preferences.favorite, connected.contains(favorite) { return favorite }
        return connected.first
    }

    /// Up to three pinned providers in the user's order; falls back to the first connected ones.
    public var pinnedProviders: [ProviderID] {
        let connected = self.connectedProviders
        let pinned = self.preferences.pinned.filter { connected.contains($0) }
        if !pinned.isEmpty { return Array(pinned.prefix(AppPreferences.maxPinned)) }
        return Array(connected.prefix(AppPreferences.maxPinned))
    }

    public func isStale(_ provider: ProviderID) -> Bool {
        switch self.status(for: provider) {
        case .offline, .expired, .failed: self.reading(for: provider) != nil
        default: false
        }
    }

    // MARK: - Preferences

    public func setFavorite(_ provider: ProviderID?) {
        self.mutatePreferences { $0.favorite = provider }
    }

    public func setPinned(_ providers: [ProviderID]) {
        var seen = Set<ProviderID>()
        let unique = providers.filter { seen.insert($0).inserted }
        self.mutatePreferences { $0.pinned = Array(unique.prefix(AppPreferences.maxPinned)) }
    }

    public func togglePinned(_ provider: ProviderID) {
        var pinned = self.pinnedProviders
        if let index = pinned.firstIndex(of: provider) {
            pinned.remove(at: index)
        } else if pinned.count < AppPreferences.maxPinned {
            pinned.append(provider)
        }
        self.setPinned(pinned)
    }

    public func movePinned(fromOffsets source: IndexSet, toOffset destination: Int) {
        let pinned = self.pinnedProviders
        let moving = source.map { pinned[$0] }
        var remaining = pinned.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        self.setPinned(remaining)
    }

    public func setRefreshInterval(minutes: Int) {
        self.mutatePreferences { $0.refreshIntervalMinutes = max(1, min(60, minutes)) }
    }

    public func setShowMenuBarItemAlways(_ value: Bool) {
        self.mutatePreferences { $0.showMenuBarItemAlways = value }
    }

    public func setDisplayName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mutatePreferences { $0.displayName = trimmed.isEmpty ? "Kazoo" : trimmed }
    }

    public func setDemoMode(_ enabled: Bool) {
        guard enabled != self.preferences.demoMode else { return }
        for provider in ProviderID.allCases { self.bumpGeneration(provider) }
        self.mutatePreferences { $0.demoMode = enabled }
        self.demoReadings = enabled ? Fixtures.allReadings(now: self.clock()) : [:]
        if !enabled { self.refreshAll(manual: false) }
    }

    private func mutatePreferences(_ change: (inout AppPreferences) -> Void) {
        var prefs = self.preferences
        change(&prefs)
        self.preferences = prefs
        self.preferencesStore.save(prefs)
    }

    // MARK: - Connect / disconnect

    /// Verifies a connection by fetching the first reading. On success the account is saved (and its secret
    /// stored in Keychain); on failure nothing is saved except a "signed in · usage unavailable" account.
    @discardableResult
    public func connect(
        _ provider: ProviderID,
        secret: String? = nil,
        workspaceID: String? = nil,
        sourceOverride: String? = nil) async -> Result<UsageReading, FetchFailure>
    {
        if self.isDemo { self.setDemoMode(false) }
        self.bumpGeneration(provider)
        let gen = self.generation[provider, default: 0]
        self.statuses[provider] = .connecting
        let storedSecret = secret ?? self.secrets.secret(for: provider)
        let request = FetchRequest(
            provider: provider,
            secret: storedSecret,
            workspaceID: workspaceID ?? self.account(for: provider)?.workspaceID,
            sourceOverride: sourceOverride ?? self.account(for: provider)?.sourceOverride,
            interactive: true)
        self.lastAttempt[provider] = self.clock()
        let result = await Self.run(self.liveSource, request)
        guard self.generation[provider, default: 0] == gen else { return .failure(.other("Cancelled")) }

        switch result {
        case let .success(reading):
            if let secret { try? self.secrets.setSecret(secret, for: provider) }
            self.upsertAccount(provider, workspaceID: request.workspaceID, sourceOverride: request.sourceOverride,
                               hasSecret: storedSecret != nil, identityKey: reading.identity?.accountKey)
            self.applySuccess(reading, provider: provider)
        case let .failure(failure):
            if case .usageUnavailable = failure {
                if let secret { try? self.secrets.setSecret(secret, for: provider) }
                self.upsertAccount(provider, workspaceID: request.workspaceID, sourceOverride: request.sourceOverride,
                                   hasSecret: storedSecret != nil, identityKey: nil)
                self.statuses[provider] = failure.connectionStatus
            } else if self.account(for: provider) != nil {
                self.statuses[provider] = failure.connectionStatus
            } else {
                self.statuses[provider] = .notConnected
            }
        }
        return result
    }

    /// Cancels an in-progress connect for `provider` (browser/device authorization or verification fetch).
    public func cancelConnect(_ provider: ProviderID) {
        self.bumpGeneration(provider)
        self.statuses[provider] = self.account(for: provider) == nil ? .notConnected : .connected
    }

    public func disconnect(_ provider: ProviderID) {
        self.bumpGeneration(provider)
        try? self.secrets.setSecret(nil, for: provider)
        self.liveReadings[provider] = nil
        self.statuses[provider] = nil
        self.failureCount[provider] = nil
        self.backoffUntil[provider] = nil
        self.resetRefreshRequested[provider] = nil
        self.mutatePreferences { prefs in
            prefs.accounts.removeAll { $0.provider == provider }
            prefs.pinned.removeAll { $0 == provider }
            if prefs.favorite == provider { prefs.favorite = prefs.accounts.first?.provider }
        }
        self.cache.save(self.liveReadings)
    }

    private func upsertAccount(
        _ provider: ProviderID,
        workspaceID: String?,
        sourceOverride: String?,
        hasSecret: Bool,
        identityKey: String?)
    {
        self.mutatePreferences { prefs in
            if let index = prefs.accounts.firstIndex(where: { $0.provider == provider }) {
                prefs.accounts[index].workspaceID = workspaceID
                prefs.accounts[index].sourceOverride = sourceOverride
                prefs.accounts[index].hasStoredSecret = hasSecret
                if let identityKey { prefs.accounts[index].identityKey = identityKey }
            } else {
                prefs.accounts.append(ConnectedAccount(
                    provider: provider, connectedAt: self.clock(), workspaceID: workspaceID,
                    sourceOverride: sourceOverride, hasStoredSecret: hasSecret, identityKey: identityKey))
                if prefs.favorite == nil { prefs.favorite = provider }
                if prefs.pinned.count < AppPreferences.maxPinned, !prefs.pinned.contains(provider) {
                    prefs.pinned.append(provider)
                }
            }
        }
    }

    // MARK: - Refresh

    public func startAutoRefresh() {
        self.timer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        self.refreshAll(manual: false)
    }

    public func stopAutoRefresh() {
        self.timer?.invalidate()
        self.timer = nil
    }

    /// Called every 30 s: updates `now`, refreshes due providers, and confirms any reset that has passed.
    public func tick() {
        self.now = self.clock()
        let interval = TimeInterval(self.preferences.refreshIntervalMinutes * 60)
        for provider in self.connectedProviders {
            if let reading = self.reading(for: provider), let passed = self.passedReset(in: reading),
               self.resetRefreshRequested[provider] != passed
            {
                self.resetRefreshRequested[provider] = passed
                self.refresh(provider, manual: false, ignoreBackoff: true)
                continue
            }
            let last = self.lastAttempt[provider] ?? .distantPast
            if self.now.timeIntervalSince(last) >= interval { self.refresh(provider, manual: false) }
        }
    }

    private func passedReset(in reading: UsageReading) -> Date? {
        reading.meters.compactMap(\.resetsAt).filter { $0 <= self.now && $0 > reading.fetchedAt }.max()
    }

    public func refreshAll(manual: Bool) {
        for provider in self.connectedProviders { self.refresh(provider, manual: manual) }
    }

    /// Starts a refresh unless one is already running (duplicates join the in-flight request).
    public func refresh(_ provider: ProviderID, manual: Bool, ignoreBackoff: Bool = false) {
        guard self.isConnected(provider), self.inFlight[provider] == nil else { return }
        if !manual, !ignoreBackoff, let until = self.backoffUntil[provider], until > self.clock() { return }
        let gen = self.generation[provider, default: 0]
        let demo = self.isDemo
        let source = demo ? self.demoSource : self.liveSource
        let account = self.account(for: provider)
        let request = FetchRequest(
            provider: provider,
            secret: demo ? nil : self.secrets.secret(for: provider),
            workspaceID: account?.workspaceID,
            sourceOverride: account?.sourceOverride,
            interactive: manual)
        self.lastAttempt[provider] = self.clock()
        self.refreshing.insert(provider)
        self.inFlight[provider] = Task { [weak self] in
            let result = await Self.run(source, request)
            guard let self else { return }
            self.finish(provider: provider, generation: gen, demo: demo, result: result)
        }
    }

    /// Awaits any in-flight refreshes (used by tests and the "Refresh" button's spinner).
    public func waitForRefreshes() async {
        while let task = self.inFlight.values.first {
            await task.value
        }
    }

    public func inFlightCount() -> Int { self.inFlight.count }

    private func finish(provider: ProviderID, generation gen: Int, demo: Bool, result: Result<UsageReading, FetchFailure>) {
        guard self.generation[provider, default: 0] == gen, demo == self.isDemo else {
            // Stale: the account was disconnected, switched, or the mode changed while this request was in flight.
            if self.generation[provider, default: 0] == gen { self.inFlight[provider] = nil }
            return
        }
        self.inFlight[provider] = nil
        self.refreshing.remove(provider)
        switch result {
        case let .success(reading):
            if demo {
                self.demoReadings[provider] = reading
            } else {
                self.applySuccess(reading, provider: provider)
            }
        case let .failure(failure):
            self.applyFailure(failure, provider: provider)
        }
    }

    private func applySuccess(_ reading: UsageReading, provider: ProviderID) {
        // An account switch (different identity than the connected one) replaces the old data immediately.
        if let key = reading.identity?.accountKey, let account = self.account(for: provider),
           account.identityKey != nil, account.identityKey != key
        {
            self.mutatePreferences { prefs in
                if let i = prefs.accounts.firstIndex(where: { $0.provider == provider }) { prefs.accounts[i].identityKey = key }
            }
            self.resetRefreshRequested[provider] = nil
        }
        self.failureCount[provider] = 0
        self.backoffUntil[provider] = nil
        self.liveReadings[provider] = reading
        self.statuses[provider] = reading.meters.isEmpty
            ? .usageUnavailable("Signed in, but \(provider.displayName) reported no usage for this account.")
            : .connected
        self.cache.save(self.liveReadings)
    }

    private func applyFailure(_ failure: FetchFailure, provider: ProviderID) {
        let count = (self.failureCount[provider] ?? 0) + 1
        self.failureCount[provider] = count
        switch failure {
        case let .rateLimited(retryAfter):
            let delay = retryAfter ?? Self.backoffDelay(failures: count)
            self.backoffUntil[provider] = self.clock().addingTimeInterval(delay)
            if self.statuses[provider] == .connecting { self.statuses[provider] = .connected }
        case .offline, .other:
            self.backoffUntil[provider] = self.clock().addingTimeInterval(Self.backoffDelay(failures: count))
            self.statuses[provider] = failure.connectionStatus
        case .expired, .notSignedIn:
            // A connected account whose sign-in disappeared or was rejected needs the same recovery: sign in again.
            self.statuses[provider] = .expired
        case .usageUnavailable, .needsPermission:
            self.statuses[provider] = failure.connectionStatus
        }
        // The last good reading is intentionally kept; views show its age.
    }

    /// 1 min, 2 min, 4 min … capped at 30 min.
    public nonisolated static func backoffDelay(failures: Int) -> TimeInterval {
        min(1800, 60 * pow(2, Double(max(0, failures - 1))))
    }

    func setStatusForPreview(_ status: ConnectionStatus, _ provider: ProviderID) {
        self.statuses[provider] = status
    }

    private func bumpGeneration(_ provider: ProviderID) {
        self.generation[provider, default: 0] += 1
        self.inFlight[provider]?.cancel()
        self.inFlight[provider] = nil
        self.refreshing.remove(provider)
    }

    private nonisolated static func run(_ source: any UsageSource, _ request: FetchRequest) async
        -> Result<UsageReading, FetchFailure>
    {
        do {
            return try await .success(source.fetch(request))
        } catch {
            return .failure(error)
        }
    }
}
