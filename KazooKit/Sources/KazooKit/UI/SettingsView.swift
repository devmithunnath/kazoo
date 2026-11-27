import ServiceManagement
import SwiftUI

/// Native Settings: favorite, pinned order, display, refresh, demo, about.
public struct SettingsView: View {
    @ObservedObject var store: UsageStore
    let openConnections: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var showNotices = false

    public init(store: UsageStore, openConnections: @escaping () -> Void) {
        self.store = store
        self.openConnections = openConnections
    }

    public var body: some View {
        Form {
            Section("Collapsed notch") {
                if self.store.connectedProviders.isEmpty {
                    Text("Connect a provider to choose a favorite.").foregroundStyle(.secondary)
                } else {
                    Picker("Favorite provider", selection: Binding(
                        get: { self.store.favoriteProvider },
                        set: { self.store.setFavorite($0) }))
                    {
                        ForEach(self.store.connectedProviders) { provider in
                            Text(provider.displayName).tag(Optional(provider))
                        }
                    }
                    Text("The favorite’s name and one reading sit on either side of the camera.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Pinned in overview (up to \(AppPreferences.maxPinned))") {
                let pinned = self.store.pinnedProviders
                ForEach(Array(pinned.enumerated()), id: \.element) { index, provider in
                    HStack {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(provider.displayName)
                        Spacer()
                        Button { self.move(provider, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(provider.displayName) up")
                        Button { self.move(provider, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == pinned.count - 1)
                            .accessibilityLabel("Move \(provider.displayName) down")
                        Button { self.store.togglePinned(provider) } label: { Image(systemName: "pin.slash") }
                            .accessibilityLabel("Unpin \(provider.displayName)")
                    }
                    .buttonStyle(.borderless)
                }
                let unpinned = self.store.connectedProviders.filter { !pinned.contains($0) }
                if !unpinned.isEmpty, pinned.count < AppPreferences.maxPinned {
                    Menu("Pin a provider") {
                        ForEach(unpinned) { provider in
                            Button(provider.displayName) { self.store.togglePinned(provider) }
                        }
                    }
                }
                if self.store.connectedProviders.isEmpty {
                    Text("No connected providers yet.").foregroundStyle(.secondary)
                }
            }

            Section("General") {
                TextField("Display name", text: Binding(
                    get: { self.store.preferences.displayName },
                    set: { self.store.setDisplayName($0) }))
                Picker("Refresh every", selection: Binding(
                    get: { self.store.preferences.refreshIntervalMinutes },
                    set: { self.store.setRefreshInterval(minutes: $0) }))
                {
                    ForEach([2, 5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Toggle("Always show menu bar item", isOn: Binding(
                    get: { self.store.preferences.showMenuBarItemAlways },
                    set: { self.store.setShowMenuBarItemAlways($0) }))
                Text("On displays without a notch, Kazoo always uses the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Open at login", isOn: Binding(
                    get: { self.launchAtLogin },
                    set: { self.setLaunchAtLogin($0) }))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Accounts") {
                Button("Open Connections…", action: self.openConnections)
                Toggle("Demo mode (sample data)", isOn: Binding(
                    get: { self.store.isDemo },
                    set: { self.store.setDemoMode($0) }))
                Text("Demo mode shows labeled sample readings for every provider. It never mixes with live data.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Provider engine", value: "CodexBarCore v0.85.0 (5dd48ca)")
                Button("Third-party notices…") { self.showNotices = true }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
        .sheet(isPresented: self.$showNotices) { NoticesView() }
    }

    private func move(_ provider: ProviderID, by offset: Int) {
        var pinned = self.store.pinnedProviders
        guard let index = pinned.firstIndex(of: provider) else { return }
        let target = index + offset
        guard pinned.indices.contains(target) else { return }
        pinned.swapAt(index, target)
        self.store.setPinned(pinned)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            self.launchAtLogin = enabled
            self.launchError = nil
        } catch {
            self.launchError = "Couldn’t change login item: \(error.localizedDescription)"
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

struct NoticesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Third-party notices").font(.title2.bold())
            ScrollView {
                Text(Self.text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Done") { self.dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 640, height: 520)
    }

    static var text: String {
        guard let url = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Notices unavailable." }
        return text
    }
}
