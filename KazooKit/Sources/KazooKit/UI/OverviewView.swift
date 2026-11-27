import SwiftUI

/// Up to three pinned providers side by side, plus "All N providers".
struct OverviewView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var router: PanelRouter

    var body: some View {
        let pinned = self.store.pinnedProviders
        VStack(alignment: .leading, spacing: 18) {
            Text("Pinned providers").font(KazooTheme.title(28))
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(pinned.enumerated()), id: \.element) { index, provider in
                    if index > 0 {
                        Rectangle().fill(KazooTheme.divider).frame(width: 1).padding(.horizontal, 26)
                    }
                    OverviewColumn(store: self.store, provider: provider) {
                        self.router.push(.detail(provider))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            GreenPill(title: "All \(self.store.connectedProviders.count) providers") {
                self.router.push(.allProviders)
            }
        }
    }
}

struct OverviewColumn: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderID
    let open: () -> Void

    var body: some View {
        Button(action: self.open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(self.provider.shortName == "OpenAI" ? "OpenAI API" : self.provider.shortName)
                        .font(KazooTheme.title(24))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KazooTheme.secondaryText)
                }
                self.content
            }
            .frame(width: 190, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityText)
        .accessibilityHint("Opens \(self.provider.displayName) details")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var content: some View {
        let status = self.store.status(for: self.provider)
        if let reading = self.store.reading(for: self.provider), let meter = reading.summaryMeter {
            VStack(alignment: .leading, spacing: 8) {
                if let gauge = meter.gauge {
                    SquareGrid(gauge: gauge, columns: 7, rows: 7, square: 22, spacing: 6)
                } else {
                    NumeralText(meter: meter, size: 78)
                        .frame(height: 196, alignment: .top)
                        .padding(.top, 22)
                }
                if meter.gauge != nil {
                    NumeralText(meter: meter, size: 46)
                        .padding(.top, 10)
                } else if case .count = meter.value {
                    EmptyView()
                }
                Text(Self.caption(for: meter))
                    .font(.system(size: 17))
                    .foregroundStyle(KazooTheme.secondaryText)
                    .lineLimit(1)
                if self.store.isStale(self.provider) {
                    Label("\(status.label) · \(ResetFormatter.age(of: reading.fetchedAt, now: self.store.now))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(KazooTheme.warning)
                }
            }
        } else {
            StatusPlaceholder(status: status)
                .frame(height: 260, alignment: .topLeading)
        }
    }

    static func caption(for meter: Meter) -> String {
        switch meter.value {
        case .money where meter.id == "today": "Spent today"
        case .count(_, _, let unit): unit
        default: meter.title
        }
    }

    private var accessibilityText: String {
        guard let meter = self.store.reading(for: self.provider)?.summaryMeter else {
            return "\(self.provider.displayName), \(self.store.status(for: self.provider).label)"
        }
        return MeterAccessibility.label(provider: self.provider, meter: meter, now: self.store.now)
    }
}

struct StatusPlaceholder: View {
    let status: ConnectionStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status == .connecting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: status.isProblem ? "exclamationmark.triangle.fill" : "hourglass")
                    .foregroundStyle(status.isProblem ? KazooTheme.warning : KazooTheme.secondaryText)
            }
            Text(status == .connected ? "Waiting for first reading…" : status.label)
                .font(.system(size: 15, weight: .medium))
            if let detail = status.detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(KazooTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }
}
