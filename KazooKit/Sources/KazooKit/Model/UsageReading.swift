import Foundation

/// Whether a meter applies to the whole account or only to one model.
public enum MeterScope: String, Codable, Sendable, Equatable {
    case account
    case model
}

/// The value a meter carries. Each case keeps its own unit so labels can never be confused.
public enum MeterValue: Codable, Sendable, Equatable {
    /// Remaining allowance, 0...100, as reported (or derived from a reported used percentage).
    case remainingPercent(Double)
    /// A dollar (or other currency) amount. Never drawn as a gauge.
    case money(amount: Double, currencyCode: String)
    /// A count such as credits used. `limit` is set only when the provider (or the user) supplied a denominator.
    case count(used: Double, limit: Double?, unit: String)
    /// The provider did not report this value. Distinct from zero.
    case unavailable(reason: String)
}

/// One window or figure inside a provider reading, e.g. "5-hour session" or "Spent today".
public struct Meter: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Full title shown above the big numeral, e.g. "Weekly · all models".
    public var title: String
    /// Lower-case short label for the collapsed notch, e.g. "weekly", "5h", "today".
    public var shortTitle: String
    public var value: MeterValue
    public var scope: MeterScope
    /// Provider timestamp for the next reset, when reported.
    public var resetsAt: Date?
    /// Provider text when only a description (no timestamp) was reported.
    public var resetDescription: String?
    /// Optional secondary caption, e.g. "of $20.00 limit".
    public var caption: String?

    public init(
        id: String,
        title: String,
        shortTitle: String,
        value: MeterValue,
        scope: MeterScope = .account,
        resetsAt: Date? = nil,
        resetDescription: String? = nil,
        caption: String? = nil)
    {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.value = value
        self.scope = scope
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.caption = caption
    }

    public var isAvailable: Bool {
        if case .unavailable = self.value { return false }
        return true
    }

    /// The remaining percentage when this meter is a percentage meter.
    public var remainingPercent: Double? {
        if case let .remainingPercent(value) = self.value { return value }
        return nil
    }

    /// The gauge fraction (0...1) or nil when no gauge may be drawn.
    /// Derived from the same rounded integer that the label prints, so squares and text always agree.
    public var gauge: GaugeValue? {
        switch self.value {
        case let .remainingPercent(percent):
            return GaugeValue(percent: GaugeMath.displayPercent(percent))
        case let .count(used, limit?, _) where limit > 0:
            let remaining = max(0, limit - used) / limit * 100
            return GaugeValue(percent: GaugeMath.displayPercent(remaining))
        default:
            return nil
        }
    }
}

/// A rounded integer percentage that drives both the label and the lit-square count.
public struct GaugeValue: Sendable, Equatable {
    public let percent: Int
    public init(percent: Int) { self.percent = min(100, max(0, percent)) }
    public func litSquares(total: Int) -> Int { GaugeMath.litSquares(percent: self.percent, total: total) }
}

/// One day of spend for the compact OpenAI chart.
public struct DailySpend: Codable, Sendable, Equatable, Identifiable {
    public var day: Date
    public var amount: Double
    public var id: Date { self.day }
    public init(day: Date, amount: Double) {
        self.day = day
        self.amount = amount
    }
}

/// The account or workspace a reading belongs to.
public struct AccountIdentity: Codable, Sendable, Equatable {
    public var email: String?
    public var organization: String?
    public var workspace: String?
    public var plan: String?

    public init(email: String? = nil, organization: String? = nil, workspace: String? = nil, plan: String? = nil) {
        self.email = email
        self.organization = organization
        self.workspace = workspace
        self.plan = plan
    }

    /// Best single line for UI ("you@example.com · Pro").
    public var summary: String? {
        let who = self.email ?? self.workspace ?? self.organization
        let parts = [who, self.plan].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Stable key used to detect an account change between readings.
    public var accountKey: String? {
        (self.email ?? self.workspace ?? self.organization)?.lowercased()
    }
}

/// The green strip at the bottom of a detail card: a label on the left and a value on the right.
public struct FooterStrip: Codable, Sendable, Equatable {
    public enum Value: Codable, Sendable, Equatable {
        case countdown(Date)
        case date(Date)
        case month(Date)
        case text(String)
    }

    public var label: String
    public var value: Value

    public init(label: String, value: Value) {
        self.label = label
        self.value = value
    }
}

/// A normalized usage reading for one connected provider account.
public struct UsageReading: Codable, Sendable, Equatable {
    public var provider: ProviderID
    public var meters: [Meter]
    public var spendHistory: [DailySpend]
    public var identity: AccountIdentity?
    /// Where the data came from (e.g. "oauth", "codex-cli", "api", "Demo").
    public var sourceLabel: String
    public var footer: FooterStrip?
    /// Subtitle under the provider name, e.g. "Organization spend" or "Workspace".
    public var subtitle: String?
    public var fetchedAt: Date
    public var isDemo: Bool

    public init(
        provider: ProviderID,
        meters: [Meter],
        spendHistory: [DailySpend] = [],
        identity: AccountIdentity? = nil,
        sourceLabel: String,
        footer: FooterStrip? = nil,
        subtitle: String? = nil,
        fetchedAt: Date = Date(),
        isDemo: Bool = false)
    {
        self.provider = provider
        self.meters = meters
        self.spendHistory = spendHistory
        self.identity = identity
        self.sourceLabel = sourceLabel
        self.footer = footer
        self.subtitle = subtitle
        self.fetchedAt = fetchedAt
        self.isDemo = isDemo
    }

    public var accountMeters: [Meter] { self.meters.filter { $0.scope == .account } }
    public var modelMeters: [Meter] { self.meters.filter { $0.scope == .model } }

    /// The one reading shown in the collapsed notch and overview column.
    ///
    /// Codex and Claude use the lowest remaining percentage among account-wide windows, so a model-specific limit
    /// can never make the whole account look exhausted. Others use their first available meter.
    public var summaryMeter: Meter? {
        if self.provider.summarizesLowestAccountWindow {
            let candidates = self.accountMeters.filter { $0.remainingPercent != nil }
            if let lowest = candidates.min(by: { ($0.remainingPercent ?? 0) < ($1.remainingPercent ?? 0) }) {
                return lowest
            }
        }
        return self.meters.first(where: \.isAvailable) ?? self.meters.first
    }
}
