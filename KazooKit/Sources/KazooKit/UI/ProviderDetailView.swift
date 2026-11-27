import SwiftUI

/// All applicable windows for one provider, each with its own value and reset.
struct ProviderDetailView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var router: PanelRouter
    let provider: ProviderID
    let actions: PanelActions

    var body: some View {
        let reading = self.store.reading(for: self.provider)
        let status = self.store.status(for: self.provider)
        VStack(alignment: .leading, spacing: 0) {
            BackButton(router: self.router).padding(.bottom, 10)
            Text(self.provider.displayName)
                .font(.system(size: 38, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if let subtitle = self.subtitle(reading) {
                Text(subtitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(KazooTheme.secondaryText)
                    .padding(.top, 2)
            }
            if let reading, reading.provider == .opencode, reading.subtitle == "Workspace" {
                Capsule().fill(KazooTheme.mint).frame(width: 64, height: 4).padding(.top, 10)
            }

            if status.isProblem || self.store.isStale(self.provider) {
                StatusBanner(store: self.store, provider: self.provider, status: status, actions: self.actions)
                    .padding(.top, 14)
            }

            Group {
                if let reading, !reading.meters.isEmpty {
                    self.meters(reading)
                } else {
                    StatusPlaceholder(status: status).padding(.vertical, 18)
                }
            }
            .padding(.top, 22)
        }
    }

    private func subtitle(_ reading: UsageReading?) -> String? {
        guard let reading else { return nil }
        var parts: [String] = []
        if let subtitle = reading.subtitle { parts.append(subtitle) }
        if let identity = reading.identity?.summary { parts.append(identity) }
        if reading.isDemo { parts.append("Sample data") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private func meters(_ reading: UsageReading) -> some View {
        let main = reading.accountMeters.isEmpty ? reading.modelMeters : reading.accountMeters
        let extra = reading.accountMeters.isEmpty ? [] : reading.modelMeters
        VStack(alignment: .leading, spacing: 22) {
            if main.count == 1, let only = main.first {
                HeroMeter(meter: only, now: self.store.now)
            } else {
                ForEach(Array(stride(from: 0, to: main.count, by: 3)), id: \.self) { start in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(main[start..<min(start + 3, main.count)].enumerated()), id: \.element.id) { index, meter in
                            if index > 0 {
                                Rectangle().fill(KazooTheme.divider).frame(width: 1).padding(.horizontal, 32)
                            }
                            MeterColumn(meter: meter, now: self.store.now,
                                        numeralSize: meter.gauge == nil ? 72 : 60)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !extra.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Model-specific limits")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KazooTheme.tertiaryText)
                        .textCase(.uppercase)
                    ForEach(extra) { meter in ModelMeterRow(meter: meter, now: self.store.now) }
                }
                .padding(.top, 2)
            }

            if !reading.spendHistory.isEmpty {
                SpendBars(history: reading.spendHistory)
            }

            if let footer = reading.footer {
                SteppedStrip(label: footer.label, value: footer.valueText(now: self.store.now))
            } else if main.count == 1, let only = main.first, let resetsAt = only.resetsAt,
                      let countdown = ResetFormatter.countdown(to: resetsAt, now: self.store.now)
            {
                SteppedStrip(label: "Resets in", value: countdown)
            }
        }
    }
}

/// Explains a problem (expired, offline, unavailable) and offers exactly one recovery action.
struct StatusBanner: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderID
    let status: ConnectionStatus
    let actions: PanelActions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: self.status == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(KazooTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title).font(.system(size: 14, weight: .semibold))
                if let detail = self.status.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(KazooTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if let action = SetupGuide.guide(for: self.provider).recoveryAction(for: self.status) {
                Button(action) {
                    switch self.status {
                    case .offline, .failed: self.store.refresh(self.provider, manual: true)
                    default: self.actions.openConnections(self.provider)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    private var title: String {
        if let reading = self.store.reading(for: self.provider), self.store.isStale(self.provider) {
            return "\(self.status.label) · showing reading from \(ResetFormatter.age(of: reading.fetchedAt, now: self.store.now))"
        }
        return self.status.label
    }
}

/// Every connected provider in stable order.
struct AllProvidersView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var router: PanelRouter
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackButton(router: self.router).padding(.bottom, 10)
            Text("All providers").font(.system(size: 30, weight: .bold)).padding(.bottom, 14)
            ForEach(self.store.connectedProviders) { provider in
                Button {
                    self.router.push(.detail(provider))
                } label: {
                    self.row(provider)
                }
                .buttonStyle(.plain)
                Rectangle().fill(KazooTheme.divider).frame(height: 1)
            }
            Button {
                self.actions.openConnections(nil)
            } label: {
                Label("Add or manage providers…", systemImage: "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(KazooTheme.mint)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 520, alignment: .leading)
    }

    private func row(_ provider: ProviderID) -> some View {
        let reading = self.store.reading(for: provider)
        let status = self.store.status(for: provider)
        let meter = reading?.summaryMeter
        return HStack(spacing: 14) {
            Text(provider.displayName).font(.system(size: 18, weight: .semibold))
            if self.store.pinnedProviders.contains(provider) {
                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(KazooTheme.tertiaryText)
            }
            Spacer()
            if let meter {
                if let gauge = meter.gauge {
                    SquareGrid(gauge: gauge, columns: 10, rows: 1, square: 9, spacing: 3)
                }
                Text(ValueFormatter.compact(for: meter))
                    .font(KazooTheme.numeral(22))
                    .monospacedDigit()
            } else {
                Text(status.label).font(.system(size: 14)).foregroundStyle(KazooTheme.secondaryText)
            }
            if status.isProblem {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(KazooTheme.warning)
                    .help(status.label)
            }
            Image(systemName: "chevron.right").foregroundStyle(KazooTheme.tertiaryText)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meter.map { MeterAccessibility.label(provider: provider, meter: $0, now: self.store.now) }
            ?? "\(provider.displayName), \(status.label)")
        .accessibilityAddTraits(.isButton)
    }
}
