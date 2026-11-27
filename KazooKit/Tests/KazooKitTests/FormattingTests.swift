import Foundation
import Testing
@testable import KazooKit

@Suite("Units and timing")
struct FormattingTests {
    @Test("Lit squares and label come from the same rounded value", arguments: [0.0, 0.4, 1.0, 23.5, 24.4, 50, 99.6, 100])
    func squaresMatchLabel(value: Double) {
        let meter = Meter(id: "m", title: "Weekly", shortTitle: "weekly", value: .remainingPercent(value))
        let gauge = try! #require(meter.gauge)
        #expect(ValueFormatter.numeral(for: meter) == "\(gauge.percent)%")
        #expect(gauge.litSquares(total: 42) == GaugeMath.litSquares(percent: gauge.percent, total: 42))
    }

    @Test func reportedZeroIsZeroAndNearlyEmptyIsNotEmpty() {
        #expect(GaugeMath.displayPercent(0) == 0)
        #expect(GaugeMath.litSquares(percent: 0, total: 49) == 0)
        #expect(GaugeMath.displayPercent(0.3) == 1)
        #expect(GaugeMath.litSquares(percent: 1, total: 49) == 1)
        #expect(GaugeMath.displayPercent(99.7) == 99)
        #expect(GaugeMath.litSquares(percent: 99, total: 49) == 48)
        #expect(GaugeMath.litSquares(percent: 100, total: 49) == 49)
    }

    @Test func countdownUsesProviderTimestamp() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(ResetFormatter.countdown(to: now.addingTimeInterval(48 * 60), now: now) == "48m")
        #expect(ResetFormatter.countdown(to: now.addingTimeInterval(2 * 3600 + 600), now: now) == "2h 10m")
        #expect(ResetFormatter.countdown(to: now.addingTimeInterval(4 * 86400 + 6 * 3600), now: now) == "4d 6h")
        #expect(ResetFormatter.countdown(to: now, now: now) == nil)
        let meter = Meter(id: "m", title: "t", shortTitle: "t", value: .remainingPercent(10), resetsAt: now)
        #expect(ResetFormatter.resetLine(for: meter, now: now) == "Reset due · confirming…")
    }

    @Test func moneyNeverGetsAGauge() {
        let money = Meter(id: "today", title: "Today", shortTitle: "today", value: .money(amount: 2.8, currencyCode: "USD"))
        #expect(money.gauge == nil)
        #expect(ValueFormatter.compact(for: money) == "$2.80 today")
    }

    @Test func countGaugeOnlyWithKnownDenominator() {
        let noLimit = Meter(id: "c", title: "AI credits used", shortTitle: "credits", value: .count(used: 184, limit: nil, unit: "AI credits used"))
        #expect(noLimit.gauge == nil)
        let limited = Meter(id: "c", title: "AI credits used", shortTitle: "credits", value: .count(used: 25, limit: 100, unit: "AI credits used"))
        #expect(limited.gauge?.percent == 75)
    }

    @Test func missingValueIsNotZero() {
        let missing = Meter(id: "m", title: "Weekly", shortTitle: "weekly", value: .unavailable(reason: "Not reported"))
        #expect(missing.gauge == nil)
        #expect(ValueFormatter.numeral(for: missing) == "—")
        #expect(!missing.isAvailable)
    }

    @Test func compactCollapsedLabel() {
        let meter = Meter(id: "w", title: "Weekly", shortTitle: "weekly", value: .remainingPercent(31))
        #expect(ValueFormatter.compact(for: meter) == "31% weekly left")
    }

    @Test func failureClassification() {
        #expect(FailureClassifier.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(FailureClassifier.classify(message: "HTTP 429 Too Many Requests") == .rateLimited(retryAfter: nil))
        if case .expired = FailureClassifier.classify(message: "Codex auth.json needs refresh. Reauthenticate this account") {} else {
            Issue.record("expected expired")
        }
        if case .expired = FailureClassifier.classify(URLError(.userAuthenticationRequired)) {} else { Issue.record("expected expired") }
        if case .notSignedIn = FailureClassifier.classify(message: "No available fetch strategy for cursor") {} else {
            Issue.record("expected notSignedIn")
        }
        let changed = FailureClassifier.classify(
            message: "Claude Code credentials changed (Updated just now). Click Refresh to re-grant CodexBar access.")
        #expect(changed == .needsPermission(FailureClassifier.permissionMessage))
        let reworded = CodexBarUsageSource.rewordedForKazoo(
            .notSignedIn("Claude OAuth credentials not found. Run `claude` to authenticate."))
        #expect(reworded == .notSignedIn("Claude OAuth credentials not found."))
        #expect(CodexBarUsageSource.rewordedForKazoo(.other("CodexBar failed")) == .other("Kazoo failed"))
        let closed = FailureClassifier.classify(message: "Antigravity language server not detected. Launch Antigravity and retry.")
        if case .companionNotRunning = closed {} else { Issue.record("expected companionNotRunning") }
        #expect(closed.isTransient)
        #expect(SetupGuide.guide(for: .antigravity).recoveryAction(for: closed.connectionStatus) == "Open Antigravity")
        // Claude recovers through its own CLI when Kazoo's Keychain grant was revoked by token rotation.
        #expect(CodexBarUsageSource.shouldRecoverWithOwnerCLI(
            provider: .claude, sourceOverride: nil, failure: changed, ownerCLIAvailable: true))
        #expect(CodexBarUsageSource.shouldRecoverWithOwnerCLI(
            provider: .claude, sourceOverride: "auto", failure: .expired("x"), ownerCLIAvailable: true))
        #expect(!CodexBarUsageSource.shouldRecoverWithOwnerCLI(
            provider: .claude, sourceOverride: nil, failure: changed, ownerCLIAvailable: false))
        #expect(!CodexBarUsageSource.shouldRecoverWithOwnerCLI(
            provider: .claude, sourceOverride: "oauth", failure: changed, ownerCLIAvailable: true))
        #expect(!CodexBarUsageSource.shouldRecoverWithOwnerCLI(
            provider: .claude, sourceOverride: nil, failure: .offline, ownerCLIAvailable: true))
        #expect(!CodexBarUsageSource.shouldRecoverWithOwnerCLI(
            provider: .codex, sourceOverride: nil, failure: .expired("x"), ownerCLIAvailable: true))
        #expect(CodexBarUsageSource.rewordedForKazoo(.expired(
            "Codex auth.json needs refresh. Reauthenticate this account or run `codex login` in the same Codex home."))
            == .expired("Codex auth.json needs refresh. Sign in to Codex again from Connections."))
        // Antigravity's offline fallback (conversation history, no quota) is reported as a live failure.
        let notRunning = CodexBarUsageSource.antigravityLiveFailure(diagnostic:
            "Live Antigravity usage is unavailable; showing offline data. Antigravity language server not detected. Launch Antigravity and retry.")
        if case .companionNotRunning = notRunning {} else { Issue.record("expected companionNotRunning") }
        if case .expired = CodexBarUsageSource.antigravityLiveFailure(diagnostic:
            "Live Antigravity usage is unavailable; showing offline data. Sign in to Antigravity again.") {} else {
            Issue.record("expected expired")
        }
        #expect(CodexBarUsageSource.antigravityLiveFailure(diagnostic:
            "Live Antigravity usage is unavailable; showing offline data. The Internet connection appears to be offline.")
            == .offline)
        #expect(CodexBarUsageSource.antigravityLiveFailure(diagnostic:
            "Live Antigravity usage is unavailable; showing offline data. the usage request failed (HTTP 500)")
            == .companionNotRunning("Couldn’t read live Antigravity usage (the usage request failed (HTTP 500)). "
                + "Open the Antigravity app, make sure you’re signed in, then check again."))
        #expect(FetchFailure.offline.isTransient)
        #expect(!FetchFailure.expired("x").isTransient)
    }
}
