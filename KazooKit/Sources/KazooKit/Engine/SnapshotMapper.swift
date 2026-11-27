import CodexBarCore
import Foundation

/// Converts CodexBarCore's `UsageSnapshot` into Kazoo's provider-neutral `UsageReading`.
///
/// Rules: a missing value stays unavailable, a reported zero stays zero, money is never drawn as a gauge,
/// and model-specific windows are scoped `.model` so they never drive the account summary.
public enum SnapshotMapper {
    static let copilotCreditsRowID = "copilot-seat-credits"

    public static func reading(
        for provider: ProviderID,
        usage: UsageSnapshot,
        credits: CreditsSnapshot? = nil,
        sourceLabel: String,
        metadata: ProviderMetadata? = nil,
        now: Date = Date()) -> UsageReading
    {
        var reading = UsageReading(
            provider: provider,
            meters: [],
            identity: self.identity(usage.identity),
            sourceLabel: self.sourceLabel(provider: provider, raw: sourceLabel),
            fetchedAt: now)

        switch provider {
        case .codex:
            reading.meters += self.windowMeter(usage.primary, id: "primary", fallback: ("5-hour session", "5h"))
            reading.meters += self.windowMeter(usage.secondary, id: "secondary", fallback: ("Weekly", "weekly"))
            reading.meters += self.windowMeter(usage.tertiary, id: "tertiary", fallback: ("Additional limit", "extra"),
                                               scope: .model)
            reading.meters += self.extraMeters(usage.extraRateWindows, scope: .model)

        case .claude:
            reading.meters += self.windowMeter(usage.primary, id: "primary", fallback: ("5-hour session", "5h"))
            reading.meters += self.windowMeter(usage.secondary, id: "secondary",
                                               fallback: ("Weekly · all models", "weekly"),
                                               forceTitle: usage.secondary?.windowMinutes == 10080 || usage.secondary?.title == nil)
            let modelLabel = metadata?.opusLabel ?? "model"
            reading.meters += self.windowMeter(usage.tertiary, id: "tertiary",
                                               fallback: ("Weekly · \(modelLabel)", modelLabel), scope: .model,
                                               forceTitle: usage.tertiary?.title == nil)
            reading.meters += self.extraMeters(usage.extraRateWindows, scope: .model)

        case .gemini:
            reading.meters += self.windowMeter(usage.primary, id: "primary", fallback: ("Pro", "Pro"), scope: .model,
                                               forceTitle: usage.primary?.title == nil)
            reading.meters += self.windowMeter(usage.secondary, id: "secondary", fallback: ("Flash", "Flash"),
                                               scope: .model, forceTitle: usage.secondary?.title == nil)
            reading.meters += self.windowMeter(usage.tertiary, id: "tertiary", fallback: ("Flash Lite", "Flash Lite"),
                                               scope: .model, forceTitle: usage.tertiary?.title == nil)
            reading.meters += self.extraMeters(usage.extraRateWindows, scope: .model)

        case .antigravity:
            reading.meters = self.antigravityMeters(usage)

        case .cursor:
            reading.meters += self.windowMeter(usage.primary, id: "primary", fallback: ("Included plan usage", "plan"),
                                               forceTitle: true)
            reading.meters += self.windowMeter(usage.secondary, id: "secondary",
                                               fallback: ("Auto + Composer", "auto"), scope: .model)
            reading.meters += self.windowMeter(usage.tertiary, id: "tertiary", fallback: ("API models", "API"),
                                               scope: .model)
            if let cost = usage.providerCost {
                let caption = cost.limit > 0
                    ? "of \(ValueFormatter.money(cost.limit, currencyCode: cost.currencyCode)) limit" : nil
                reading.meters.append(Meter(
                    id: "on-demand", title: "On-demand spend", shortTitle: "on-demand",
                    value: .money(amount: cost.used, currencyCode: cost.currencyCode), caption: caption))
            }
            if let cycleEnd = usage.primary?.resetsAt ?? usage.providerCost?.resetsAt {
                reading.footer = FooterStrip(label: "Billing cycle ends", value: .date(cycleEnd))
            }

        case .copilot:
            let premium = self.windowMeter(usage.primary, id: "primary", fallback: ("Premium requests", "premium"),
                                           forceTitle: true)
            let chat = self.windowMeter(usage.secondary, id: "secondary", fallback: ("Chat", "chat"), forceTitle: true)
            let creditRow = usage.details.flatMap(\.rows).first { $0.id == self.copilotCreditsRowID }
            var creditMeter: Meter?
            if let row = creditRow, let used = row.usageValue {
                let limit = row.progress.map(\.total).flatMap { $0 > 0 ? $0 : nil }
                creditMeter = Meter(
                    id: "credits", title: "AI credits used", shortTitle: "credits",
                    value: .count(used: used, limit: limit, unit: "AI credits used"),
                    caption: limit.map { "of \(ValueFormatter.count($0)) included" })
            }
            if premium.isEmpty, let creditMeter {
                reading.meters = [creditMeter] + chat
            } else {
                reading.meters = premium + chat + (creditMeter.map { [$0] } ?? [])
            }
            if let resetsAt = usage.primary?.resetsAt ?? usage.secondary?.resetsAt {
                let periodDay = resetsAt.addingTimeInterval(-86400)
                reading.footer = FooterStrip(label: "Billing period", value: .month(periodDay))
            }

        case .opencode:
            reading.subtitle = "Workspace"
            let isSubscription = usage.primary?.windowMinutes == 300
            if isSubscription {
                reading.meters += self.windowMeter(usage.primary, id: "primary", fallback: ("5-hour", "5h"),
                                                   forceTitle: true)
                reading.meters += self.windowMeter(usage.secondary, id: "secondary", fallback: ("Weekly", "weekly"),
                                                   forceTitle: true)
                if let plan = usage.identity?.loginMethod, !plan.isEmpty { reading.subtitle = "\(plan) subscription" }
            }
            if let cost = usage.providerCost {
                reading.meters.append(Meter(
                    id: "spend", title: cost.period ?? "Last 30 days", shortTitle: "30d",
                    value: .money(amount: cost.used, currencyCode: cost.currencyCode),
                    caption: "Spend"))
                if let balance = cost.balance {
                    reading.meters.append(Meter(
                        id: "balance", title: "Prepaid balance", shortTitle: "balance",
                        value: .money(amount: balance, currencyCode: cost.currencyCode)))
                } else {
                    reading.meters.append(Meter(
                        id: "balance", title: "Prepaid balance", shortTitle: "balance",
                        value: .unavailable(reason: "Not reported")))
                }
                if !isSubscription, let limitWindow = usage.primary?.measured {
                    reading.meters.append(Meter(
                        id: "limit", title: "Monthly spend limit", shortTitle: "limit",
                        value: .remainingPercent(limitWindow.remainingPercent)))
                }
            }
            if let renewal = usage.extraRateWindows?.first(where: { $0.id == "renewal" })?.window.resetsAt {
                reading.footer = FooterStrip(label: "Renews", value: .date(renewal))
            }

        case .openai:
            reading.subtitle = "Organization spend"
            if let api = usage.openAIAPIUsage {
                reading.meters.append(Meter(
                    id: "today", title: "Today", shortTitle: "today",
                    value: .money(amount: api.currentDay.costUSD, currencyCode: "USD")))
                reading.meters.append(Meter(
                    id: "last7", title: "Last 7 days", shortTitle: "7d",
                    value: .money(amount: api.last7Days.costUSD, currencyCode: "USD")))
                reading.spendHistory = api.daily
                    .sorted { $0.startTime < $1.startTime }
                    .suffix(7)
                    .map { DailySpend(day: $0.startTime, amount: $0.costUSD) }
                if let project = api.projectID { reading.identity?.workspace = project }
            }
        }

        return reading
    }

    // MARK: - Antigravity

    static let antigravitySummaryPrefix = "antigravity-quota-summary-"

    /// Antigravity reports two real pools (Gemini, Claude + GPT). Quota-summary buckets (session/weekly per pool)
    /// become the main meters; otherwise the pool representatives are used. Per-model rows are listed as
    /// model-specific, and rows without a remaining fraction (reset context only) are skipped, never shown as empty.
    static func antigravityMeters(_ usage: UsageSnapshot) -> [Meter] {
        let extras = usage.extraRateWindows ?? []
        let summary = extras.filter { $0.id.hasPrefix(self.antigravitySummaryPrefix) }
        if !summary.isEmpty {
            return summary.map { named in
                let short = self.antigravityShortTitle(named.title)
                guard named.usageKnown, let measured = named.window.measured else {
                    return Meter(id: named.id, title: named.title, shortTitle: short,
                                 value: .unavailable(reason: "Not reported"))
                }
                return Meter(id: named.id, title: named.title, shortTitle: short,
                             value: .remainingPercent(measured.remainingPercent),
                             resetsAt: measured.resetsAt, resetDescription: measured.resetDescription)
            }
        }
        var meters: [Meter] = []
        meters += self.windowMeter(usage.primary, id: "primary", fallback: ("Gemini", "gemini"), forceTitle: true)
        meters += self.windowMeter(usage.secondary, id: "secondary", fallback: ("Claude + GPT", "claude/gpt"),
                                   forceTitle: true)
        meters += self.extraMeters(extras.filter(\.usageKnown), scope: .model)
        return meters
    }

    /// "Claude + GPT Weekly" → "claude weekly", "Gemini Session" → "gemini session" (fits the notch wing).
    static func antigravityShortTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "claude + gpt", with: "claude")
            .replacingOccurrences(of: "claude/gpt", with: "claude")
    }

    // MARK: - Helpers

    static func windowMeter(
        _ window: RateWindow?,
        id: String,
        fallback: (title: String, short: String),
        scope: MeterScope = .account,
        forceTitle: Bool = false) -> [Meter]
    {
        guard let window else { return [] }
        let titles = forceTitle ? fallback : self.titles(for: window, fallback: fallback)
        guard let measured = window.measured else {
            return [Meter(id: id, title: titles.title, shortTitle: titles.short,
                          value: .unavailable(reason: "Not reported"), scope: scope)]
        }
        return [Meter(
            id: id,
            title: titles.title,
            shortTitle: titles.short,
            value: .remainingPercent(measured.remainingPercent),
            scope: scope,
            resetsAt: measured.resetsAt,
            resetDescription: measured.resetDescription)]
    }

    static func extraMeters(_ extras: [NamedRateWindow]?, scope: MeterScope) -> [Meter] {
        (extras ?? []).filter { $0.id != "renewal" }.map { named in
            guard named.usageKnown, let measured = named.window.measured else {
                return Meter(id: "extra-\(named.id)", title: named.title, shortTitle: named.title,
                             value: .unavailable(reason: "Not reported"), scope: scope)
            }
            return Meter(
                id: "extra-\(named.id)",
                title: named.title,
                shortTitle: named.title,
                value: .remainingPercent(measured.remainingPercent),
                scope: scope,
                resetsAt: measured.resetsAt,
                resetDescription: measured.resetDescription)
        }
    }

    static func titles(for window: RateWindow, fallback: (title: String, short: String)) -> (title: String, short: String) {
        switch window.windowMinutes {
        case 300?: return ("5-hour session", "5h")
        case 10080?: return ("Weekly", "weekly")
        case 1440?: return ("Daily", "daily")
        default:
            if let title = window.title, !title.isEmpty { return (title, title.lowercased()) }
            return fallback
        }
    }

    static func identity(_ snapshot: ProviderIdentitySnapshot?) -> AccountIdentity? {
        guard let snapshot else { return nil }
        let identity = AccountIdentity(
            email: snapshot.accountEmail?.nilIfBlank,
            organization: snapshot.accountOrganization?.nilIfBlank,
            plan: snapshot.loginMethod?.nilIfBlank)
        return identity.summary == nil ? nil : identity
    }

    static func sourceLabel(provider: ProviderID, raw: String) -> String {
        if provider == .gemini { return "Gemini CLI" }
        if provider == .antigravity {
            switch raw.lowercased() {
            case let s where s.contains("cli") || s.contains("agy"): return "Antigravity CLI"
            case let s where s.contains("oauth"): return "Google account"
            case let s where s.contains("offline"): return "Offline history"
            case let s where s.contains("local") || s.contains("app"): return "Antigravity app"
            default: return raw
            }
        }
        return raw
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
