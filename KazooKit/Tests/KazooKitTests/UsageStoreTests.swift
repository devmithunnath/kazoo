import Foundation
import Testing
@testable import KazooKit

@MainActor
@Suite("Store behavior")
struct UsageStoreTests {
    @Test func firstConnectionBecomesFavoriteAndFirstThreeArePinned() async {
        let source = ScriptedSource()
        let store = makeStore(source: source)
        for p in [ProviderID.codex, .claude, .openai, .cursor] {
            await source.enqueue(p, .success(Make.percentReading(p, [("w", 50, .account)])))
            _ = await store.connect(p)
        }
        #expect(store.favoriteProvider == .codex)
        #expect(store.pinnedProviders == [.codex, .claude, .openai])
        #expect(store.connectedProviders == [.codex, .claude, .openai, .cursor])
    }

    @Test func orderStaysStableDuringRefresh() async {
        let source = ScriptedSource()
        let store = makeStore(source: source)
        for p in [ProviderID.claude, .codex, .gemini] {
            await source.enqueue(p, .success(Make.percentReading(p, [("w", 50, .account)])))
            _ = await store.connect(p)
        }
        for p in [ProviderID.gemini, .codex, .claude] {
            await source.enqueue(p, .success(Make.percentReading(p, [("w", 10, .account)])))
        }
        store.refreshAll(manual: true)
        await store.waitForRefreshes()
        #expect(store.connectedProviders == [.claude, .codex, .gemini])
        #expect(store.pinnedProviders == [.claude, .codex, .gemini])
    }

    @Test func duplicateRefreshJoinsInFlightRequest() async {
        let source = ScriptedSource()
        let store = makeStore(source: source)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("w", 50, .account)])))
        _ = await store.connect(.codex)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("w", 40, .account)])))
        await source.setGate(true)
        store.refresh(.codex, manual: true)
        store.refresh(.codex, manual: true)
        store.refresh(.codex, manual: false)
        #expect(store.inFlightCount() == 1)
        await source.setGate(false)
        await store.waitForRefreshes()
        #expect(await source.callCount(.codex) == 2) // connect + one refresh
        #expect(store.reading(for: .codex)?.meters.first?.remainingPercent == 40)
    }

    @Test func expiredSignInKeepsLastReadingAndFlagsRecovery() async {
        let source = ScriptedSource()
        let store = makeStore(source: source)
        await source.enqueue(.claude, .success(Make.percentReading(.claude, [("w", 70, .account)])))
        _ = await store.connect(.claude)
        await source.enqueue(.claude, .failure(.expired("token expired")))
        store.refresh(.claude, manual: true)
        await store.waitForRefreshes()
        #expect(store.status(for: .claude) == .expired)
        #expect(store.reading(for: .claude)?.meters.first?.remainingPercent == 70)
        #expect(store.isStale(.claude))
        #expect(SetupGuide.guide(for: .claude).recoveryAction(for: .expired) == "Sign in again")
    }

    @Test func offlineKeepsCachedReadingWithAgeAndBacksOff() async {
        let clock = TestClock()
        let source = ScriptedSource()
        let store = makeStore(source: source, clock: clock)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("w", 70, .account)], fetchedAt: clock.now)))
        _ = await store.connect(.codex)
        await source.enqueue(.codex, .failure(.offline))
        clock.advance(600)
        store.refresh(.codex, manual: true)
        await store.waitForRefreshes()
        #expect(store.status(for: .codex) == .offline)
        #expect(store.reading(for: .codex) != nil)
        #expect(store.isStale(.codex))
        #expect(ResetFormatter.age(of: store.reading(for: .codex)!.fetchedAt, now: clock.now) == "10m ago")
        // Automatic refresh is suppressed during backoff; a manual refresh is still allowed.
        store.refresh(.codex, manual: false)
        #expect(store.inFlightCount() == 0)
    }

    @Test func rateLimitBacksOffAutomaticRefresh() async {
        let clock = TestClock()
        let source = ScriptedSource()
        let store = makeStore(source: source, clock: clock)
        await source.enqueue(.cursor, .success(Make.percentReading(.cursor, [("w", 70, .account)])))
        _ = await store.connect(.cursor)
        await source.enqueue(.cursor, .failure(.rateLimited(retryAfter: 300)))
        store.refresh(.cursor, manual: true)
        await store.waitForRefreshes()
        store.refresh(.cursor, manual: false)
        #expect(store.inFlightCount() == 0)
        clock.advance(301)
        await source.enqueue(.cursor, .success(Make.percentReading(.cursor, [("w", 60, .account)])))
        store.refresh(.cursor, manual: false)
        #expect(store.inFlightCount() == 1)
        await store.waitForRefreshes()
        #expect(UsageStore.backoffDelay(failures: 1) == 60)
        #expect(UsageStore.backoffDelay(failures: 10) == 1800)
    }

    @Test func disconnectWhileInFlightDiscardsResultAndClearsData() async {
        let source = ScriptedSource()
        let cache = MemoryReadingCache()
        let store = makeStore(source: source, cache: cache)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("w", 70, .account)])))
        _ = await store.connect(.codex)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("w", 10, .account)], email: "other@example.com")))
        await source.setGate(true)
        store.refresh(.codex, manual: true)
        store.disconnect(.codex)
        #expect(store.reading(for: .codex) == nil) // cleared immediately
        await source.setGate(false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.reading(for: .codex) == nil)
        #expect(!store.isConnected(.codex))
        #expect(cache.load()[.codex] == nil)
    }

    @Test func accountSwitchReplacesPreviousAccountData() async {
        let source = ScriptedSource()
        let store = makeStore(source: source)
        await source.enqueue(.claude, .success(Make.percentReading(.claude, [("w", 70, .account)], email: "first@example.com")))
        _ = await store.connect(.claude)
        await source.enqueue(.claude, .success(Make.percentReading(.claude, [("w", 15, .account)], email: "second@example.com")))
        store.refresh(.claude, manual: true)
        await store.waitForRefreshes()
        #expect(store.reading(for: .claude)?.identity?.email == "second@example.com")
        #expect(store.account(for: .claude)?.identityKey == "second@example.com")
    }

    @Test func passedResetTriggersOneConfirmationRefresh() async {
        let clock = TestClock()
        let source = ScriptedSource()
        let store = makeStore(source: source, clock: clock)
        let reset = clock.now.addingTimeInterval(120)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("5h", 5, .account)], resetsAt: reset, fetchedAt: clock.now)))
        _ = await store.connect(.codex)
        store.tick() // within interval and before reset: nothing due
        #expect(store.inFlightCount() == 0)
        clock.advance(130)
        // The provider has not replenished yet: same stale value until confirmed.
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("5h", 5, .account)], resetsAt: reset, fetchedAt: clock.now)))
        store.tick()
        #expect(store.inFlightCount() == 1)
        await store.waitForRefreshes()
        store.tick() // same passed reset must not loop
        #expect(store.inFlightCount() == 0)
        #expect(store.reading(for: .codex)?.meters.first?.remainingPercent == 5)
    }

    @Test func onlyUserActionsMayPromptForPermission() async {
        let clock = TestClock()
        let source = ScriptedSource()
        let store = makeStore(source: source, clock: clock)
        await source.enqueue(.claude, .success(Make.percentReading(.claude, [("w", 70, .account)])),
                             .success(Make.percentReading(.claude, [("w", 60, .account)])),
                             .failure(.needsPermission(FailureClassifier.permissionMessage)))
        _ = await store.connect(.claude)            // user clicked connect
        store.refresh(.claude, manual: true)        // user clicked refresh
        await store.waitForRefreshes()
        clock.advance(3600)
        store.tick()                                 // automatic
        await store.waitForRefreshes()
        #expect(await source.interactiveFlags == [true, true, false])
        if case .failed = store.status(for: .claude) {} else { Issue.record("expected failed status") }
        #expect(store.reading(for: .claude)?.meters.first?.remainingPercent == 60) // last reading kept
    }

    @Test func backgroundRefreshNeverPromptsForSavedKey() async {
        let source = ScriptedSource()
        let secrets = MemorySecretStore()
        let store = makeStore(source: source, secrets: secrets)
        await source.enqueue(.openai, .success(UsageReading(provider: .openai, meters: [
            Meter(id: "today", title: "Today", shortTitle: "today", value: .money(amount: 1, currencyCode: "USD")),
        ], sourceLabel: "api")))
        _ = await store.connect(.openai, secret: "sk-admin-test")
        // After an app update macOS would have to ask before the key can be read.
        secrets.promptRequired = [.openai]
        store.refresh(.openai, manual: false)
        await store.waitForRefreshes()
        #expect(await source.callCount(.openai) == 1) // no fetch without the key, and no prompt
        #expect(store.status(for: .openai) == .failed(FailureClassifier.savedKeyPermissionMessage))
        #expect(store.reading(for: .openai) != nil) // last reading kept
        // "Try again" is a user action: the key is read interactively and the refresh proceeds.
        await source.enqueue(.openai, .success(UsageReading(provider: .openai, meters: [
            Meter(id: "today", title: "Today", shortTitle: "today", value: .money(amount: 2, currencyCode: "USD")),
        ], sourceLabel: "api")))
        store.refresh(.openai, manual: true)
        await store.waitForRefreshes()
        #expect(store.status(for: .openai) == .connected)
        #expect(store.reading(for: .openai)?.meters.first?.value == .money(amount: 2, currencyCode: "USD"))
    }

    @Test func signedInButNoUsageIsAConnectedState() async {
        let source = ScriptedSource()
        let store = makeStore(source: source)
        await source.enqueue(.copilot, .failure(.usageUnavailable("Your plan doesn’t report usage")))
        let result = await store.connect(.copilot, secret: "gho_test")
        #expect((try? result.get()) == nil)
        #expect(store.isConnected(.copilot))
        if case .usageUnavailable = store.status(for: .copilot) {} else { Issue.record("expected usageUnavailable") }
    }

    @Test func failedKeyIsNotSaved() async {
        let source = ScriptedSource()
        let secrets = MemorySecretStore()
        let store = makeStore(source: source, secrets: secrets)
        await source.enqueue(.openai, .failure(.expired("401 Unauthorized")))
        _ = await store.connect(.openai, secret: "sk-admin-bad")
        #expect(!store.isConnected(.openai))
        #expect(secrets.secret(for: .openai) == nil)
        await source.enqueue(.openai, .success(UsageReading(provider: .openai, meters: [
            Meter(id: "today", title: "Today", shortTitle: "today", value: .money(amount: 1, currencyCode: "USD")),
        ], sourceLabel: "api")))
        _ = await store.connect(.openai, secret: "sk-admin-good")
        #expect(store.isConnected(.openai))
        #expect(secrets.secret(for: .openai) == "sk-admin-good")
        store.disconnect(.openai)
        #expect(secrets.secret(for: .openai) == nil)
    }

    @Test func demoModeNeverMixesWithLiveData() async {
        let source = ScriptedSource()
        let cache = MemoryReadingCache()
        let store = makeStore(source: source, cache: cache)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("w", 70, .account)])))
        _ = await store.connect(.codex)
        store.setDemoMode(true)
        #expect(store.connectedProviders.count == ProviderID.allCases.count)
        #expect(store.reading(for: .codex)?.isDemo == true)
        #expect(cache.load()[.codex]?.isDemo == false)
        await source.enqueue(.codex, .success(Make.percentReading(.codex, [("w", 65, .account)])))
        store.setDemoMode(false)
        await store.waitForRefreshes()
        #expect(store.connectedProviders == [.codex])
        #expect(store.reading(for: .codex)?.isDemo == false)
    }

    @Test func pinnedReorderAndLimit() async {
        let source = ScriptedSource()
        let store = makeStore(source: source)
        for p in [ProviderID.codex, .claude, .openai, .cursor] {
            await source.enqueue(p, .success(Make.percentReading(p, [("w", 50, .account)])))
            _ = await store.connect(p)
        }
        store.movePinned(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.pinnedProviders == [.openai, .codex, .claude])
        store.togglePinned(.cursor) // already three pinned: ignored
        #expect(store.pinnedProviders == [.openai, .codex, .claude])
        store.setFavorite(.cursor)
        #expect(store.favoriteProvider == .cursor)
    }

    @Test func relaunchRestoresAccountsAndCachedReadings() async {
        let source = ScriptedSource()
        let prefsStore = MemoryPreferences()
        let cache = MemoryReadingCache()
        let first = UsageStore(liveSource: source, secrets: MemorySecretStore(), preferences: prefsStore, cache: cache)
        await source.enqueue(.gemini, .success(Make.percentReading(.gemini, [("Pro", 42, .model)])))
        _ = await first.connect(.gemini)
        let second = UsageStore(liveSource: source, secrets: MemorySecretStore(), preferences: prefsStore, cache: cache)
        #expect(second.connectedProviders == [.gemini])
        #expect(second.reading(for: .gemini)?.meters.first?.remainingPercent == 42)
    }
}

@MainActor
@Suite("Panel routing")
struct PanelRouterTests {
    @Test func oneProviderOpensDetailDirectlyAndSeveralOpenOverview() async {
        let one = PreviewSupport.store(providers: [.copilot])
        let router = PanelRouter()
        router.reset(for: one)
        #expect(router.current == .detail(.copilot))
        #expect(!router.canGoBack)

        let many = PreviewSupport.store(providers: [.codex, .claude, .openai])
        router.reset(for: many)
        #expect(router.current == .overview)
        router.push(.allProviders)
        router.push(.detail(.claude))
        #expect(router.backTitle == "All providers")
        router.back()
        #expect(router.current == .allProviders)

        let none = PreviewSupport.store(providers: [])
        router.reset(for: none)
        #expect(router.current == .empty)
    }

    @Test func providerSearch() {
        #expect(ProviderID.copilot.matches(search: "github"))
        #expect(ProviderID.openai.matches(search: "admin"))
        #expect(!ProviderID.cursor.matches(search: "gemini"))
        #expect(ProviderID.allCases.filter { $0.matches(search: "") }.count == 8)
    }
}
