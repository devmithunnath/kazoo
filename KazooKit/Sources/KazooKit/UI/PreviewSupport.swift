import SwiftUI

/// Fixture-backed stores for SwiftUI previews, snapshot renders, and tests. Never used for live accounts.
@MainActor
public enum PreviewSupport {
    public static func store(
        providers: [ProviderID],
        favorite: ProviderID? = nil,
        pinned: [ProviderID]? = nil,
        statuses: [ProviderID: ConnectionStatus] = [:]) -> UsageStore
    {
        var prefs = AppPreferences()
        prefs.accounts = providers.map { ConnectedAccount(provider: $0) }
        prefs.favorite = favorite ?? providers.first
        prefs.pinned = pinned ?? Array(providers.prefix(3))
        let cache = MemoryReadingCache()
        var readings = Fixtures.allReadings()
        for key in readings.keys { readings[key]?.isDemo = false; readings[key]?.sourceLabel = "fixture" }
        cache.save(readings)
        let store = UsageStore(
            liveSource: DemoUsageSource(),
            secrets: MemorySecretStore(),
            preferences: MemoryPreferences(prefs),
            cache: cache)
        for (provider, status) in statuses { store.debugSetStatus(status, for: provider) }
        return store
    }

    public static func panel(store: UsageStore, route: PanelRoute, back: PanelRoute? = nil) -> some View {
        let router = PanelRouter()
        router.reset(for: store)
        if let back { router.push(back) }
        router.push(route)
        return NotchHostedPanel(store: store, router: router, actions: PanelActions(), topInset: 32)
    }
}

extension UsageStore {
    /// Preview/test hook to show a specific status without a network call.
    public func debugSetStatus(_ status: ConnectionStatus, for provider: ProviderID) {
        self.setStatusForPreview(status, provider)
    }
}

#Preview("Collapsed · Codex") {
    CollapsedNotchView(store: PreviewSupport.store(providers: [.codex, .claude]), notchWidth: 185, wingWidth: 110, height: 32)
        .padding()
}

#Preview("Overview · three pinned") {
    PreviewSupport.panel(store: PreviewSupport.store(providers: [.codex, .claude, .openai, .cursor]), route: .overview)
}

#Preview("Detail · Claude") {
    PreviewSupport.panel(store: PreviewSupport.store(providers: [.codex, .claude]), route: .detail(.claude), back: .overview)
}

#Preview("Detail · Copilot") {
    PreviewSupport.panel(store: PreviewSupport.store(providers: [.copilot]), route: .detail(.copilot))
}

#Preview("Connections") {
    ConnectionsView(store: PreviewSupport.store(providers: [.codex]), selection: .constant(.openai))
}
