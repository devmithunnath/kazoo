import CodexBarCore
import Foundation
import Testing
@testable import KazooKit

@Suite("CodexBarCore snapshot mapping (fixture-tested)")
struct SnapshotMapperTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func window(_ used: Double, minutes: Int?, reset: TimeInterval?, title: String? = nil) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: reset.map { self.now.addingTimeInterval($0) },
                   resetDescription: nil, title: title)
    }

    @Test func codexTwoWindowsWithIndependentResets() {
        let usage = UsageSnapshot(
            primary: self.window(32, minutes: 300, reset: 7800),
            secondary: self.window(69, minutes: 10080, reset: 273_600),
            updatedAt: self.now,
            identity: ProviderIdentitySnapshot(providerID: nil, accountEmail: "me@example.com", accountOrganization: nil, loginMethod: "plus"))
        let reading = SnapshotMapper.reading(for: .codex, usage: usage, sourceLabel: "oauth", now: self.now)
        #expect(reading.meters.map(\.title) == ["5-hour session", "Weekly"])
        #expect(reading.meters[0].remainingPercent == 68)
        #expect(reading.meters[1].remainingPercent == 31)
        #expect(reading.meters[0].resetsAt != reading.meters[1].resetsAt)
        #expect(reading.summaryMeter?.id == "secondary") // lowest account window
        #expect(ValueFormatter.compact(for: reading.summaryMeter!) == "31% weekly left")
        #expect(reading.identity?.email == "me@example.com")
    }

    @Test func codexOneWindowAccount() {
        let usage = UsageSnapshot(primary: self.window(10, minutes: 300, reset: 600), secondary: nil, updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .codex, usage: usage, sourceLabel: "oauth", now: self.now)
        #expect(reading.meters.count == 1)
        #expect(reading.summaryMeter?.remainingPercent == 90)
    }

    @Test func claudeModelLimitDoesNotExhaustAccount() {
        let usage = UsageSnapshot(
            primary: self.window(76, minutes: 300, reset: 2880),
            secondary: self.window(24, minutes: 10080, reset: 367_200),
            tertiary: self.window(100, minutes: 10080, reset: 367_200),
            updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .claude, usage: usage, sourceLabel: "oauth", now: self.now)
        #expect(reading.accountMeters.map(\.title) == ["5-hour session", "Weekly · all models"])
        #expect(reading.modelMeters.count == 1)
        #expect(reading.modelMeters[0].remainingPercent == 0) // reported zero displays as zero
        #expect(reading.summaryMeter?.remainingPercent == 24) // not 0
    }

    @Test func missingWindowStaysMissing() {
        let usage = UsageSnapshot(primary: self.window(8, minutes: 300, reset: 600), secondary: nil, updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .claude, usage: usage, sourceLabel: "claude", now: self.now)
        #expect(!reading.meters.contains { $0.id == "secondary" })
    }

    @Test func syntheticPlaceholderIsUnavailableNotZero() {
        let placeholder = RateWindow(usedPercent: 0, windowMinutes: 10080, resetsAt: nil, resetDescription: nil,
                                     isSyntheticPlaceholder: true)
        let usage = UsageSnapshot(primary: self.window(50, minutes: 300, reset: 60), secondary: placeholder, updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .codex, usage: usage, sourceLabel: "oauth", now: self.now)
        let weekly = reading.meters.first { $0.id == "secondary" }
        #expect(weekly?.isAvailable == false)
        #expect(reading.summaryMeter?.remainingPercent == 50)
    }

    @Test func geminiBucketsAndSourceLabel() {
        let usage = UsageSnapshot(
            primary: self.window(58, minutes: 1440, reset: 21600),
            secondary: self.window(13, minutes: 1440, reset: 21600),
            updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .gemini, usage: usage, sourceLabel: "api", now: self.now)
        #expect(reading.meters.map(\.title) == ["Pro", "Flash"])
        #expect(reading.meters.allSatisfy { $0.scope == .model })
        #expect(reading.sourceLabel == "Gemini CLI")
        #expect(reading.summaryMeter?.title == "Pro")
    }

    @Test func cursorPlanAndOnDemandSpend() {
        let usage = UsageSnapshot(
            primary: self.window(48, minutes: nil, reset: 432_000),
            secondary: nil,
            providerCost: ProviderCostSnapshot(used: 3.8, limit: 20, currencyCode: "USD", updatedAt: self.now),
            updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .cursor, usage: usage, sourceLabel: "web", now: self.now)
        #expect(reading.meters.first?.title == "Included plan usage")
        let onDemand = try! #require(reading.meters.first { $0.id == "on-demand" })
        #expect(onDemand.value == .money(amount: 3.8, currencyCode: "USD"))
        #expect(onDemand.gauge == nil)
        #expect(reading.footer?.label == "Billing cycle ends")
    }

    @Test func copilotCreditsWithoutDenominatorGetNoGauge() throws {
        let json = #"[{"title":"Credits","rows":[{"id":"copilot-seat-credits","label":"Credits used","value":"184","usageValue":184}]}]"#
        let details = try JSONDecoder().decode([ProviderDetailSection].self, from: Data(json.utf8))
        let usage = UsageSnapshot(primary: nil, secondary: nil, details: details, updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .copilot, usage: usage, sourceLabel: "api", now: self.now)
        let credits = try #require(reading.meters.first)
        #expect(credits.value == .count(used: 184, limit: nil, unit: "AI credits used"))
        #expect(credits.gauge == nil)
    }

    @Test func copilotPremiumQuotaWithBillingPeriod() {
        let usage = UsageSnapshot(primary: self.window(40, minutes: nil, reset: 86400 * 5), secondary: nil, updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .copilot, usage: usage, sourceLabel: "api", now: self.now)
        #expect(reading.meters.first?.title == "Premium requests")
        #expect(reading.meters.first?.remainingPercent == 60)
        #expect(reading.footer?.label == "Billing period")
    }

    @Test func openAISpendOnlyNeverGetsPercentGauge() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: self.now)
        let buckets = (0..<10).map { i -> OpenAIAPIUsageSnapshot.DailyBucket in
            let start = cal.date(byAdding: .day, value: -i, to: today)!
            return OpenAIAPIUsageSnapshot.DailyBucket(
                day: "d\(i)", startTime: start, endTime: start.addingTimeInterval(86400), costUSD: Double(i) + 1,
                requests: 1, inputTokens: 1, cachedInputTokens: 0, outputTokens: 1, totalTokens: 2, lineItems: [], models: [])
        }
        let api = OpenAIAPIUsageSnapshot(daily: buckets, updatedAt: self.now)
        let usage = UsageSnapshot(primary: nil, secondary: nil, openAIAPIUsage: api, updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .openai, usage: usage, sourceLabel: "api", now: self.now)
        #expect(reading.meters.map(\.title) == ["Today", "Last 7 days"])
        #expect(reading.meters.allSatisfy { $0.gauge == nil })
        #expect(reading.meters[0].value == .money(amount: 1, currencyCode: "USD"))
        #expect(reading.spendHistory.count == 7)
        #expect(reading.subtitle == "Organization spend")
    }

    @Test func openCodeWorkspaceSpendAndBalance() {
        let usage = UsageSnapshot(
            primary: nil, secondary: nil,
            providerCost: ProviderCostSnapshot(used: 18.6, limit: 0, currencyCode: "USD", period: "Last 30 days",
                                               balance: 7.4, updatedAt: self.now),
            updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .opencode, usage: usage, sourceLabel: "web", now: self.now)
        #expect(reading.meters.map(\.title) == ["Last 30 days", "Prepaid balance"])
        #expect(reading.meters.allSatisfy { $0.gauge == nil })
        #expect(reading.subtitle == "Workspace")
    }

    @Test func openCodeSubscriptionWindows() {
        let usage = UsageSnapshot(
            primary: self.window(20, minutes: 300, reset: 3600),
            secondary: self.window(55, minutes: 10080, reset: 86400),
            updatedAt: self.now)
        let reading = SnapshotMapper.reading(for: .opencode, usage: usage, sourceLabel: "web", now: self.now)
        #expect(reading.meters.map(\.title) == ["5-hour", "Weekly"])
    }
}
