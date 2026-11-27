import Foundation

/// Sample readings for previews, tests, and the explicitly labeled demo mode. Never used for live accounts.
public enum Fixtures {
    public static func reading(_ provider: ProviderID, now: Date = Date()) -> UsageReading {
        let h: TimeInterval = 3600
        switch provider {
        case .codex:
            return UsageReading(
                provider: .codex,
                meters: [
                    Meter(id: "primary", title: "5-hour session", shortTitle: "5h",
                          value: .remainingPercent(68), resetsAt: now.addingTimeInterval(2 * h + 600)),
                    Meter(id: "secondary", title: "Weekly", shortTitle: "weekly",
                          value: .remainingPercent(31), resetsAt: now.addingTimeInterval(76 * h)),
                ],
                identity: AccountIdentity(email: "demo@example.com", plan: "Plus"),
                sourceLabel: "Demo", isDemo: true)
        case .claude:
            return UsageReading(
                provider: .claude,
                meters: [
                    Meter(id: "primary", title: "5-hour session", shortTitle: "5h",
                          value: .remainingPercent(24), resetsAt: now.addingTimeInterval(48 * 60)),
                    Meter(id: "secondary", title: "Weekly · all models", shortTitle: "weekly",
                          value: .remainingPercent(76), resetsAt: now.addingTimeInterval(102 * h)),
                    Meter(id: "tertiary", title: "Weekly · Opus", shortTitle: "Opus",
                          value: .remainingPercent(0), scope: .model, resetsAt: now.addingTimeInterval(102 * h)),
                ],
                identity: AccountIdentity(email: "demo@example.com", plan: "Max"),
                sourceLabel: "Demo", isDemo: true)
        case .cursor:
            let cycleEnd = Calendar.current.date(byAdding: .day, value: 5, to: now) ?? now
            return UsageReading(
                provider: .cursor,
                meters: [
                    Meter(id: "primary", title: "Included plan usage", shortTitle: "plan",
                          value: .remainingPercent(52), resetsAt: cycleEnd),
                    Meter(id: "on-demand", title: "On-demand spend", shortTitle: "on-demand",
                          value: .money(amount: 3.80, currencyCode: "USD")),
                ],
                identity: AccountIdentity(email: "demo@example.com", plan: "Pro"),
                sourceLabel: "Demo",
                footer: FooterStrip(label: "Billing cycle ends", value: .date(cycleEnd)),
                isDemo: true)
        case .copilot:
            return UsageReading(
                provider: .copilot,
                meters: [
                    Meter(id: "credits", title: "AI credits used", shortTitle: "credits",
                          value: .count(used: 184, limit: nil, unit: "AI credits used")),
                ],
                identity: AccountIdentity(email: "demo-user", plan: "Pro"),
                sourceLabel: "Demo",
                footer: FooterStrip(label: "Billing period", value: .month(now)),
                isDemo: true)
        case .gemini:
            return UsageReading(
                provider: .gemini,
                meters: [
                    Meter(id: "primary", title: "Pro", shortTitle: "Pro", value: .remainingPercent(42),
                          scope: .model, resetsAt: now.addingTimeInterval(6 * h)),
                    Meter(id: "secondary", title: "Flash", shortTitle: "Flash", value: .remainingPercent(87),
                          scope: .model, resetsAt: now.addingTimeInterval(6 * h)),
                ],
                identity: AccountIdentity(email: "demo@example.com"),
                sourceLabel: "Demo · Gemini CLI", isDemo: true)
        case .opencode:
            return UsageReading(
                provider: .opencode,
                meters: [
                    Meter(id: "spend", title: "Last 30 days", shortTitle: "30d",
                          value: .money(amount: 18.60, currencyCode: "USD"), caption: "Spend"),
                    Meter(id: "balance", title: "Prepaid balance", shortTitle: "balance",
                          value: .money(amount: 7.40, currencyCode: "USD")),
                ],
                identity: AccountIdentity(workspace: "demo-workspace"),
                sourceLabel: "Demo", subtitle: "Workspace", isDemo: true)
        case .openai:
            let cal = Calendar.current
            let today = cal.startOfDay(for: now)
            let amounts = [2.40, 3.10, 2.30, 1.60, 2.70, 4.50, 2.80]
            let history = amounts.enumerated().map { index, amount in
                DailySpend(day: cal.date(byAdding: .day, value: index - 6, to: today) ?? today, amount: amount)
            }
            return UsageReading(
                provider: .openai,
                meters: [
                    Meter(id: "today", title: "Today", shortTitle: "today", value: .money(amount: 2.80, currencyCode: "USD")),
                    Meter(id: "last7", title: "Last 7 days", shortTitle: "7d", value: .money(amount: 19.40, currencyCode: "USD")),
                ],
                spendHistory: history,
                identity: AccountIdentity(organization: "Demo org"),
                sourceLabel: "Demo", subtitle: "Organization spend", isDemo: true)
        }
    }

    public static func allReadings(now: Date = Date()) -> [ProviderID: UsageReading] {
        Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, self.reading($0, now: now)) })
    }
}

/// Demo source: returns fixtures after a short delay. Only used when demo mode is explicitly on.
public struct DemoUsageSource: UsageSource {
    public init() {}
    public func fetch(_ request: FetchRequest) async throws(FetchFailure) -> UsageReading {
        try? await Task.sleep(nanoseconds: 250_000_000)
        return Fixtures.reading(request.provider)
    }
}
