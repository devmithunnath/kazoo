import SwiftUI

/// Root of the expanded notch panel (also used inside the menu-bar popover).
public struct NotchPanelView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var router: PanelRouter
    let actions: PanelActions
    /// Height reserved at the top for the camera housing (0 in the menu-bar popover).
    let topInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: UsageStore, router: PanelRouter, actions: PanelActions, topInset: CGFloat) {
        self.store = store
        self.router = router
        self.actions = actions
        self.topInset = topInset
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: self.topInset)
            Group {
                switch self.router.current {
                case .empty:
                    EmptyPanelView(actions: self.actions)
                case .overview:
                    OverviewView(store: self.store, router: self.router)
                case .allProviders:
                    AllProvidersView(store: self.store, router: self.router, actions: self.actions)
                case let .detail(provider):
                    ProviderDetailView(store: self.store, router: self.router, provider: provider, actions: self.actions)
                }
            }
            .transition(.opacity)
            PanelFooter(store: self.store, router: self.router, actions: self.actions)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 18)
        .frame(minWidth: 420, alignment: .leading)
        .fixedSize()
        .background(KazooTheme.panel)
        .foregroundStyle(KazooTheme.primaryText)
        .environment(\.colorScheme, .dark)
        .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.18), value: self.router.current)
        .background(KeyboardShortcuts(router: self.router, store: self.store, actions: self.actions))
    }
}

/// Hidden buttons that provide keyboard shortcuts inside the panel.
private struct KeyboardShortcuts: View {
    @ObservedObject var router: PanelRouter
    @ObservedObject var store: UsageStore
    let actions: PanelActions

    var body: some View {
        ZStack {
            Button("Back") { self.router.back() }.keyboardShortcut(.leftArrow, modifiers: [.command])
            Button("Back") { self.router.back() }.keyboardShortcut("[", modifiers: [.command])
            Button("Refresh") { self.store.refreshAll(manual: true) }.keyboardShortcut("r", modifiers: [.command])
            Button("Settings") { self.actions.openSettings() }.keyboardShortcut(",", modifiers: [.command])
            ForEach(Array(self.store.pinnedProviders.enumerated()), id: \.offset) { index, provider in
                Button("Open \(provider.displayName)") { self.router.push(.detail(provider)) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

struct BackButton: View {
    @ObservedObject var router: PanelRouter
    var body: some View {
        if self.router.canGoBack {
            Button {
                self.router.back()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Text(self.router.backTitle).font(.system(size: 17))
                }
                .foregroundStyle(KazooTheme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(self.router.backTitle)")
        }
    }
}

struct EmptyPanelView: View {
    let actions: PanelActions
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No providers connected").font(KazooTheme.title(24))
            Text("Connect Codex, Claude, Cursor, Copilot, Gemini CLI, Antigravity, OpenCode, or the OpenAI API to see how much you have left.")
                .font(.system(size: 14))
                .foregroundStyle(KazooTheme.secondaryText)
                .frame(width: 380, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            GreenPill(title: "Connect a provider") { self.actions.openConnections(nil) }
                .frame(width: 380)
        }
        .padding(.vertical, 12)
    }
}

/// Bottom row: data age, refresh, settings. Kept quiet so the readings dominate.
struct PanelFooter: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var router: PanelRouter
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 14) {
            if self.store.isDemo {
                Label("Demo data", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KazooTheme.warning)
            } else if let age = self.ageText {
                Text(age).font(.system(size: 12)).foregroundStyle(KazooTheme.tertiaryText)
            }
            Spacer()
            Button {
                self.store.refreshAll(manual: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(self.store.refreshing.isEmpty ? 0 : 180))
            }
            .buttonStyle(.plain)
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
            Button { self.actions.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
        }
        .font(.system(size: 13))
        .foregroundStyle(KazooTheme.tertiaryText)
        .padding(.top, 14)
    }

    private var ageText: String? {
        let dates: [Date]
        if case let .detail(provider) = self.router.current {
            dates = [self.store.reading(for: provider)?.fetchedAt].compactMap { $0 }
        } else {
            dates = self.store.connectedProviders.compactMap { self.store.reading(for: $0)?.fetchedAt }
        }
        guard let oldest = dates.min() else { return nil }
        return "Updated \(ResetFormatter.age(of: oldest, now: self.store.now))"
    }
}
