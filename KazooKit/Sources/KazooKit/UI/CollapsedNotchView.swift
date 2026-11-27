import SwiftUI

/// The collapsed notch: favorite provider's short name on the left wing, one meaningful reading on the right.
/// The camera area in the middle stays empty.
public struct CollapsedNotchView: View {
    @ObservedObject var store: UsageStore
    let notchWidth: CGFloat
    let wingWidth: CGFloat
    let height: CGFloat

    public init(store: UsageStore, notchWidth: CGFloat, wingWidth: CGFloat, height: CGFloat) {
        self.store = store
        self.notchWidth = notchWidth
        self.wingWidth = wingWidth
        self.height = height
    }

    public var body: some View {
        HStack(spacing: 0) {
            self.leftWing
                .frame(width: self.wingWidth, alignment: .leading)
                .padding(.leading, 14)
            Color.clear.frame(width: self.notchWidth)
            self.rightWing
                .frame(width: self.wingWidth, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .frame(height: self.height)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(KazooTheme.primaryText)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                .fill(Color.black))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityText)
        .accessibilityHint("Click to show AI usage details")
        .accessibilityAddTraits(.isButton)
    }

    private var favorite: ProviderID? { self.store.favoriteProvider }

    @ViewBuilder private var leftWing: some View {
        if let favorite {
            HStack(spacing: 5) {
                Text(favorite.shortName).lineLimit(1)
                if self.store.isDemo {
                    Text("DEMO").font(.system(size: 8, weight: .heavy)).foregroundStyle(KazooTheme.warning)
                }
            }
        } else {
            Text("AI usage").foregroundStyle(KazooTheme.secondaryText)
        }
    }

    @ViewBuilder private var rightWing: some View {
        if let favorite {
            let status = self.store.status(for: favorite)
            if let meter = self.store.reading(for: favorite)?.summaryMeter {
                HStack(spacing: 4) {
                    if status.isProblem {
                        Image(systemName: status == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(KazooTheme.warning)
                    }
                    Text(ValueFormatter.compact(for: meter))
                        .foregroundStyle(meter.remainingPercent == 0 ? KazooTheme.warning : KazooTheme.mint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else if status == .connecting || self.store.refreshing.contains(favorite) {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Text(status.label).foregroundStyle(KazooTheme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
            }
        } else {
            Text("Connect").foregroundStyle(KazooTheme.mint)
        }
    }

    private var accessibilityText: String {
        guard let favorite else { return "AI usage. No providers connected." }
        if let meter = self.store.reading(for: favorite)?.summaryMeter {
            return MeterAccessibility.label(provider: favorite, meter: meter, now: self.store.now)
        }
        return "\(favorite.displayName), \(self.store.status(for: favorite).label)"
    }
}

/// Expanded panel outline: flush with the screen top, concave fillets into the menu bar, large bottom radius.
public struct NotchPanelShape: Shape {
    public var topFillet: CGFloat = 14
    public var bottomRadius: CGFloat = 36

    public init(topFillet: CGFloat = 14, bottomRadius: CGFloat = 36) {
        self.topFillet = topFillet
        self.bottomRadius = bottomRadius
    }

    public func path(in rect: CGRect) -> Path {
        let f = self.topFillet
        let r = self.bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY + f), control: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY), control: CGPoint(x: rect.maxX - f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + f + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.maxY - r), control: CGPoint(x: rect.minX + f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + f, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The expanded panel as hosted under the notch: panel content inside the notch outline.
public struct NotchHostedPanel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var router: PanelRouter
    let actions: PanelActions
    let topInset: CGFloat

    public init(store: UsageStore, router: PanelRouter, actions: PanelActions, topInset: CGFloat) {
        self.store = store
        self.router = router
        self.actions = actions
        self.topInset = topInset
    }

    public var body: some View {
        NotchPanelView(store: self.store, router: self.router, actions: self.actions, topInset: self.topInset + 8)
            .padding(.horizontal, 14) // room for the concave fillets
            .background(KazooTheme.panel)
            .clipShape(NotchPanelShape())
    }
}
