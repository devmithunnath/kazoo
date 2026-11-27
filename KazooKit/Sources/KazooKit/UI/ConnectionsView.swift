import SwiftUI

/// Native Connections window: search, connect, verify, and recover every provider from the GUI.
public struct ConnectionsView: View {
    @ObservedObject var store: UsageStore
    @Binding var selection: ProviderID?
    @State private var search = ""
    /// Offscreen captures can't draw the translucent sidebar; screenshots use a solid one instead.
    private let solidSidebar: Bool

    public init(store: UsageStore, selection: Binding<ProviderID?>, solidSidebar: Bool = false) {
        self.store = store
        self._selection = selection
        self.solidSidebar = solidSidebar
    }

    private var filtered: [ProviderID] {
        ProviderID.allCases.filter { $0.matches(search: self.search) }
    }

    public var body: some View {
        Group {
            if self.solidSidebar {
                // Screenshot layout: same sidebar and detail, without the system-composited split-view sidebar.
                HStack(spacing: 0) {
                    self.sidebar
                        .frame(width: 270)
                        .background(Color(white: 0.95))
                    Divider()
                    self.detail
                }
            } else {
                NavigationSplitView {
                    self.sidebar
                        .navigationSplitViewColumnWidth(min: 240, ideal: 270)
                } detail: {
                    self.detail
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var sidebar: some View {
        List(selection: self.$selection) {
            if self.store.isDemo {
                Label("Demo mode — sample data", systemImage: "sparkles")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            ForEach(self.filtered) { provider in
                ProviderRow(store: self.store, provider: provider).tag(provider)
            }
            if self.filtered.isEmpty {
                Text("No provider matches “\(self.search)”.").foregroundStyle(.secondary)
            }
        }
        .modifier(SolidSidebar(enabled: self.solidSidebar))
        .searchable(text: self.$search, placement: .sidebar, prompt: "Search providers")
    }

    @ViewBuilder private var detail: some View {
        if let provider = self.selection {
            ConnectDetailView(store: self.store, provider: provider)
                .id(provider)
        } else {
            ConnectionsWelcome(store: self.store)
        }
    }
}

private struct SolidSidebar: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if self.enabled {
            content.listStyle(.inset).scrollContentBackground(.hidden).background(Color(white: 0.95))
        } else {
            content
        }
    }
}

struct StatusDot: View {
    let status: ConnectionStatus
    var body: some View {
        Circle().fill(self.color).frame(width: 8, height: 8).accessibilityHidden(true)
    }

    private var color: Color {
        switch self.status {
        case .connected: .green
        case .connecting: .blue
        case .notConnected: .gray.opacity(0.5)
        default: .orange
        }
    }
}

struct ProviderRow: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderID

    var body: some View {
        let status = self.store.status(for: self.provider)
        HStack(spacing: 10) {
            ProviderMonogram(provider: self.provider)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.provider.displayName).font(.headline)
                HStack(spacing: 5) {
                    StatusDot(status: status)
                    Text(self.subtitle(status)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ status: ConnectionStatus) -> String {
        if status == .notConnected { return SetupGuide.guide(for: self.provider).primaryAction }
        if status == .connected, let meter = self.store.reading(for: self.provider)?.summaryMeter {
            return ValueFormatter.compact(for: meter)
        }
        return status.label
    }
}

struct ProviderMonogram: View {
    let provider: ProviderID
    var body: some View {
        Text(String(self.provider.shortName.prefix(2)))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.8))
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KazooTheme.mint))
            .accessibilityHidden(true)
    }
}

struct ConnectionsWelcome: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 44))
                .foregroundStyle(KazooTheme.mint)
            Text("Connect your AI providers").font(.title2.bold())
            Text("Pick a provider on the left. Kazoo reuses sign-ins already on this Mac where it can, "
                + "and keeps any keys it stores in your Keychain.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            if self.store.isDemo {
                Button("Turn off demo mode") { self.store.setDemoMode(false) }
            } else if !self.store.hasConnections {
                Button("Explore with demo data") { self.store.setDemoMode(true) }
                    .help("Shows sample readings for every provider. Clearly labeled as demo data.")
                Text("Demo data is sample data, not your usage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConnectDetailView: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderID
    @StateObject private var model: ConnectFlowModel
    @State private var confirmDisconnect = false

    init(store: UsageStore, provider: ProviderID) {
        self.store = store
        self.provider = provider
        self._model = StateObject(wrappedValue: ConnectFlowModel(provider: provider, store: store))
    }

    var body: some View {
        let status = self.store.isDemo ? ConnectionStatus.notConnected : self.store.status(for: self.provider)
        let connected = self.store.account(for: self.provider) != nil
        Form {
            Section {
                HStack(spacing: 12) {
                    ProviderMonogram(provider: self.provider).scaleEffect(1.3).padding(4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.provider.displayName).font(.title2.bold())
                        Text(self.provider.measures).foregroundStyle(.secondary)
                    }
                }
            }

            if connected {
                self.connectedSection(status)
            }

            Section(connected ? "Reconnect" : "Connect") {
                Text(self.model.guide.permissionNote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                self.kindControls
                self.phaseView
                HStack {
                    if self.model.isBusy {
                        Button("Cancel", role: .cancel) { self.model.cancel() }
                            .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button(self.primaryTitle(connected: connected, status: status)) { self.model.primary() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(self.model.isBusy)
                }
            }

            if !self.provider.advancedSourceChoices.isEmpty {
                Section {
                    DisclosureGroup("Advanced") {
                        Picker("Data source", selection: self.$model.sourceOverride) {
                            ForEach(self.provider.advancedSourceChoices, id: \.id) { choice in
                                Text(choice.label).tag(choice.id)
                            }
                        }
                        Text("Automatic tries the most reliable source first. Change this only if a specific source "
                            + "works better for your setup.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Link("Provider notes (CodexBar docs)", destination: self.model.guide.docsURL)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(self.provider.displayName)
        .confirmationDialog("Disconnect \(self.provider.displayName)?", isPresented: self.$confirmDisconnect) {
            Button("Disconnect", role: .destructive) { self.store.disconnect(self.provider) }
        } message: {
            Text("Kazoo removes its saved data and any key it stored for this provider. "
                + "Sign-ins owned by other apps (like the \(self.model.companion?.displayName ?? "provider") CLI) are left untouched.")
        }
    }

    private func primaryTitle(connected: Bool, status: ConnectionStatus) -> String {
        if connected, let recovery = self.model.guide.recoveryAction(for: status) { return recovery }
        if connected { return "Check again" }
        if case .failed = self.model.phase { return "Check again" }
        return self.model.guide.primaryAction
    }

    @ViewBuilder private func connectedSection(_ status: ConnectionStatus) -> some View {
        Section("Status") {
            LabeledContent("Connection") {
                HStack(spacing: 6) {
                    StatusDot(status: status)
                    Text(status.label)
                }
            }
            if let detail = status.detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            if let reading = self.store.reading(for: self.provider) {
                if let identity = reading.identity?.summary {
                    LabeledContent(self.provider == .opencode ? "Workspace" : "Account", value: identity)
                }
                ForEach(reading.meters) { meter in
                    LabeledContent(meter.title) {
                        Text(self.meterValue(meter)).monospacedDigit()
                    }
                }
                LabeledContent("Source", value: reading.sourceLabel)
                LabeledContent("Updated", value: ResetFormatter.age(of: reading.fetchedAt, now: self.store.now))
            }
            HStack {
                Button("Refresh") { self.store.refresh(self.provider, manual: true) }
                    .disabled(self.store.refreshing.contains(self.provider))
                Button(self.store.favoriteProvider == self.provider ? "Favorite ✓" : "Make favorite") {
                    self.store.setFavorite(self.provider)
                }
                .disabled(self.store.favoriteProvider == self.provider)
                Button(self.store.pinnedProviders.contains(self.provider) ? "Unpin" : "Pin to overview") {
                    self.store.togglePinned(self.provider)
                }
                .disabled(!self.store.pinnedProviders.contains(self.provider)
                    && self.store.pinnedProviders.count >= AppPreferences.maxPinned)
                Spacer()
                Button("Disconnect…", role: .destructive) { self.confirmDisconnect = true }
            }
        }
    }

    private func meterValue(_ meter: Meter) -> String {
        var text = ValueFormatter.numeral(for: meter)
        if case .remainingPercent = meter.value { text += " left" }
        if case let .count(_, _, unit) = meter.value { text += " \(unit)" }
        if let reset = ResetFormatter.resetLine(for: meter, now: self.store.now) { text += " · \(reset)" }
        return text
    }

    @ViewBuilder private var kindControls: some View {
        switch self.model.guide.kind {
        case let .apiKey(keyURL, requirement, placeholder):
            Text(requirement).font(.callout).fixedSize(horizontal: false, vertical: true)
            Link("Open OpenAI Admin keys page", destination: keyURL)
            SecureField("Admin key", text: self.$model.apiKey, prompt: Text(placeholder))
                .textContentType(.password)
                .disabled(self.model.isBusy)
        case let .browserSession(signInURL, asksForWorkspace):
            Link("Open \(signInURL.host ?? "website") to sign in", destination: signInURL)
            if asksForWorkspace {
                TextField("Workspace ID (optional)", text: self.$model.workspaceID, prompt: Text("wrk_…"))
                    .disabled(self.model.isBusy)
            }
        case let .localAccount(cli):
            if let appName = cli.appName {
                LabeledContent("\(appName) app") {
                    Text(cli.appURL != nil ? "Installed" : "Not found")
                        .foregroundStyle(cli.appURL != nil ? Color.green : Color.secondary)
                }
            }
            LabeledContent(cli.displayName) {
                if let path = self.model.companionPath {
                    Text("Found").foregroundStyle(.green).help(path)
                } else {
                    Text("Not found").foregroundStyle(.secondary)
                }
            }
        case .deviceFlow:
            EmptyView()
        }
    }

    @ViewBuilder private var phaseView: some View {
        switch self.model.phase {
        case .idle:
            EmptyView()
        case .verifying:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Fetching the first reading…") }
        case .signingIn:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser. Kazoo will continue automatically.")
            }
        case .waitingForInteractiveSignIn:
            VStack(alignment: .leading, spacing: 6) {
                Text("A Terminal window opened with \(self.model.companion?.displayName ?? "the CLI"). Complete the sign-in there.")
                Button("Check again") { self.model.verify(secret: nil) }
            }
        case let .deviceCode(code):
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter this code on GitHub:").foregroundStyle(.secondary)
                Text(code.userCode)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel("Device code \(code.userCode.map(String.init).joined(separator: " "))")
                HStack {
                    Button("Copy code") { self.model.copyDeviceCode() }
                    Link("Open GitHub again", destination: code.verificationURL)
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval…").foregroundStyle(.secondary)
                }
            }
        case let .needsCompanion(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "person.crop.circle.badge.exclamationmark")
                    .fixedSize(horizontal: false, vertical: true)
                if let cli = self.model.companion {
                    if let appName = cli.appName, cli.appURL != nil {
                        HStack {
                            Button("Open \(appName)") { self.model.openCompanionApp() }
                            Button("Check again") { self.model.verify(secret: nil) }
                        }
                    } else if self.model.companionPath != nil {
                        Button(cli.browserLoginArguments == nil ? "Open \(cli.displayName) to sign in"
                                                                : "Sign in with \(cli.displayName)") {
                            self.model.signInWithCompanion()
                        }
                    } else {
                        Text("\(cli.displayName) isn’t installed on this Mac. Install it, sign in once, then check again.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Link("Install \(cli.displayName)", destination: cli.installURL)
                            Button("Check again") {
                                self.model.detectCompanion()
                                self.model.verify(secret: nil)
                            }
                        }
                    }
                }
            }
        case .done:
            let status = self.store.status(for: self.provider)
            if case .usageUnavailable = status {
                Label(status.label, systemImage: "checkmark.circle").foregroundStyle(.orange)
            } else {
                Label("Connected" + (self.store.reading(for: self.provider)?.identity?.summary.map { " as \($0)" } ?? ""),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
