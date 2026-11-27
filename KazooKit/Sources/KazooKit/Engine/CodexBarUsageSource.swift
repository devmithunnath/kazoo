// Bridges Kazoo's app-owned `UsageSource` interface to CodexBarCore (MIT, © Peter Steinberger).
// The fetch-context assembly mirrors CodexBar's CLI (`CLIUsageCommand.fetchUsageOutput`) at the pinned revision,
// trimmed to a single live account per provider and app-owned credentials.
import CodexBarCore
import Foundation

extension ProviderID {
    var coreProvider: UsageProvider {
        switch self {
        case .codex: .codex
        case .claude: .claude
        case .cursor: .cursor
        case .copilot: .copilot
        case .gemini: .gemini
        case .antigravity: .antigravity
        case .opencode: .opencode
        case .openai: .openai
        }
    }

    /// Default source for each provider. Gemini is pinned to the Gemini CLI source (the web app is out of scope).
    var defaultSourceMode: ProviderSourceMode {
        switch self {
        case .gemini, .copilot, .openai: .api
        case .opencode: .web
        case .codex, .claude, .cursor, .antigravity: .auto
        }
    }

    /// Advanced source choices offered in Connections. Only shown where the choice changes how data is read.
    public var advancedSourceChoices: [(id: String, label: String)] {
        switch self {
        case .codex: [("auto", "Automatic"), ("oauth", "Codex sign-in file"), ("cli", "Codex CLI")]
        case .claude: [("auto", "Automatic"), ("oauth", "Claude Code sign-in"), ("cli", "Claude CLI"),
                       ("web", "Browser session")]
        case .cursor: [("auto", "Automatic"), ("web", "Browser session")]
        case .antigravity: [("auto", "Automatic"), ("cli", "Antigravity CLI (agy)")]
        default: []
        }
    }
}

public struct CodexBarUsageSource: UsageSource {
    public init() {}

    /// Captures the user's login-shell PATH once so CLIs installed via Homebrew/npm resolve from a GUI app.
    public static func warmUp() {
        LoginShellPathCache.shared.captureOnce()
    }

    public func fetch(_ request: FetchRequest) async throws(FetchFailure) -> UsageReading {
        let sourceMode = request.sourceOverride.flatMap(ProviderSourceMode.init(rawValue:))
            ?? request.provider.defaultSourceMode
        if request.provider == .copilot || request.provider == .openai {
            guard let secret = request.secret, !secret.isEmpty else {
                throw .notSignedIn("No saved credential for \(request.provider.displayName).")
            }
        }
        let env = Self.environment(for: request, sourceMode: sourceMode)
        // CodexBarCore only shows Keychain/permission prompts for user-initiated fetches.
        let interaction: ProviderInteraction = request.interactive ? .userInitiated : .background
        do {
            return try await self.fetchOnce(request, sourceMode: sourceMode, env: env, interaction: interaction)
        } catch {
            guard Self.shouldRecoverWithOwnerCLI(
                provider: request.provider,
                sourceOverride: request.sourceOverride,
                failure: error,
                ownerCLIAvailable: Self.ownerCLIAvailable(for: request.provider, env: env))
            else { throw error }
            // Claude Code rotates its token and rewrites its Keychain item every few hours, which revokes
            // Kazoo's access grant. Instead of asking the user to re-allow it, read usage through the
            // `claude` CLI, which owns that Keychain item and reads it without a prompt from Kazoo.
            do {
                return try await self.fetchOnce(
                    request, sourceMode: .cli, env: env,
                    // CodexBarCore only launches the owner CLI outside its own "established" session policy
                    // for user-initiated work; Kazoo deliberately opts in for this recovery path.
                    interaction: .userInitiated)
            } catch let cliFailure {
                if case .notSignedIn = cliFailure { throw cliFailure }
                throw error
            }
        }
    }

    public static let antigravityCLIInstallCommand = "brew install --cask antigravity-cli"
    public static let antigravityTokenMessage = "Kazoo can’t read the Antigravity app’s usage: Antigravity 2.x no longer "
        + "shares the access token Kazoo needs. Install the Antigravity CLI (agy) and run it once to sign in — Kazoo "
        + "then reads your usage through it."

    /// Maps CodexBarCore's reason for Antigravity's offline fallback to a failure with one clear fix.
    static func antigravityLiveFailure(diagnostic: String?) -> FetchFailure {
        let reason = (diagnostic ?? "")
            .replacingOccurrences(of: "Live Antigravity usage is unavailable; showing offline data.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let r = reason.lowercased()
        if r.contains("csrf") {
            return .companionNotRunning(Self.antigravityTokenMessage)
        }
        if r.contains("not detected") || r.contains("launch antigravity") || r.contains("not running") || r.isEmpty {
            return .companionNotRunning("Antigravity isn’t running. Open the Antigravity app (signed in with "
                + "Google), then check again.")
        }
        if r.contains("sign in") || r.contains("signed in") || r.contains("log in") || r.contains("logged in")
            || r.contains("authenticat") || r.contains("expired") || r.contains("401") || r.contains("403")
        {
            return .expired("Antigravity needs you to sign in again. Open Antigravity and sign in with Google, "
                + "then check again.")
        }
        if r.contains("internet") || r.contains("network") || r.contains("offline") {
            return .offline
        }
        let detail = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
        return .companionNotRunning("Couldn’t read live Antigravity usage (\(detail)). Open the Antigravity app, "
            + "make sure you’re signed in, then check again.")
    }

    /// Whether a failed fetch should be retried through the provider's own CLI (no Kazoo Keychain access).
    static func shouldRecoverWithOwnerCLI(
        provider: ProviderID,
        sourceOverride: String?,
        failure: FetchFailure,
        ownerCLIAvailable: Bool) -> Bool
    {
        guard provider == .claude, ownerCLIAvailable else { return false }
        // Respect an explicit source the user picked under Advanced (other than Automatic).
        if let sourceOverride, sourceOverride != "auto" { return false }
        switch failure {
        case .needsPermission, .expired, .notSignedIn: return true
        case .offline, .rateLimited, .usageUnavailable, .companionNotRunning, .other: return false
        }
    }

    static func ownerCLIAvailable(for provider: ProviderID, env: [String: String]) -> Bool {
        switch provider {
        case .claude: BinaryLocator.resolveClaudeBinary(env: env) != nil
        default: false
        }
    }

    private static func environment(for request: FetchRequest, sourceMode: ProviderSourceMode) -> [String: String] {
        let config = Self.providerConfig(for: request, sourceMode: sourceMode)
        return ProviderEnvironmentResolver.resolve(
            base: Self.baseEnvironment(),
            provider: request.provider.coreProvider,
            config: config,
            selectedAccount: nil)
    }

    private func fetchOnce(
        _ request: FetchRequest,
        sourceMode: ProviderSourceMode,
        env: [String: String],
        interaction: ProviderInteraction) async throws(FetchFailure) -> UsageReading
    {
        let provider = request.provider.coreProvider
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        guard descriptor.fetchPlan.sourceModes.contains(sourceMode) else {
            throw .other("\(request.provider.displayName) does not support the “\(sourceMode.rawValue)” source.")
        }
        let config = Self.providerConfig(for: request, sourceMode: sourceMode)
        let settings = Self.settingsSnapshot(for: request.provider, config: config, env: env)
        let browserDetection = BrowserDetection()
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: true,
            requiresOptionalUsageCompleteness: true,
            webTimeout: 45,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: settings,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection, environment: env),
            browserDetection: browserDetection)

        let outcome = await ProviderInteractionContext.$current.withValue(interaction) {
            await descriptor.fetchOutcome(context: context)
        }
        if env["KAZOO_DEBUG_ATTEMPTS"] == "1" {
            // Developer aid (kazoo-probe): which strategies ran. Error text only, never credentials.
            for attempt in outcome.attempts {
                print("attempt \(attempt.strategyID) available=\(attempt.wasAvailable) error=\(attempt.errorDescription ?? "-")")
            }
            if case let .success(result) = outcome.result, let diagnostic = result.diagnostic {
                print("diagnostic \(diagnostic)")
            }
        }
        switch outcome.result {
        case let .success(result):
            // Antigravity's offline fallback only counts local conversations; it has no quota. Report why live
            // usage failed instead of presenting it as a signed-in account without usage.
            if request.provider == .antigravity, result.sourceLabel == "offline" {
                throw Self.antigravityLiveFailure(diagnostic: result.diagnostic)
            }
            return SnapshotMapper.reading(
                for: request.provider,
                usage: result.usage,
                credits: result.credits,
                sourceLabel: result.sourceLabel,
                metadata: descriptor.metadata)
        case let .failure(error):
            throw Self.rewordedForKazoo(FailureClassifier.classify(error))
        }
    }

    /// Upstream messages mention CodexBar's own menus and CLI commands; translate them for Kazoo's GUI.
    static func rewordedForKazoo(_ failure: FetchFailure) -> FetchFailure {
        func clean(_ m: String) -> String {
            var text = m
            let replacements: [(String, String)] = [
                ("Open the CodexBar menu and click Refresh to re-authenticate, or switch Claude Usage source to Web/CLI.",
                 "Click Check again, or choose another data source under Advanced."),
                ("Click Refresh to retry access, or switch Claude Usage source to CLI/Web.",
                 "Click Check again, or choose another data source under Advanced."),
                (" Reauthenticate this account or run `codex login` in the same Codex home.",
                 " Sign in to Codex again from Connections."),
                ("Click Refresh", "Click Check again"),
                ("CodexBar", "Kazoo"),
            ]
            for (from, to) in replacements { text = text.replacingOccurrences(of: from, with: to) }
            // Shell instructions ("Run `claude` to authenticate.") are replaced by GUI sign-in buttons.
            text = text.replacingOccurrences(of: #"\s*Run [`'‘’"][^`'‘’"]+[`'‘’"]( in Terminal)? to authenticate\.?"#,
                                             with: "", options: .regularExpression)
            return text.trimmingCharacters(in: .whitespaces)
        }
        switch failure {
        case let .notSignedIn(m): return .notSignedIn(clean(m))
        case let .expired(m): return .expired(clean(m))
        case let .usageUnavailable(m): return .usageUnavailable(clean(m))
        case let .needsPermission(m): return .needsPermission(clean(m))
        case let .companionNotRunning(m): return .companionNotRunning(clean(m))
        case let .other(m): return .other(clean(m))
        case .offline, .rateLimited: return failure
        }
    }

    static func baseEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = PathBuilder.effectivePATH(purposes: [.rpc, .tty, .nodeTooling], env: env)
        return env
    }

    static func providerConfig(for request: FetchRequest, sourceMode: ProviderSourceMode) -> ProviderConfig {
        let cookieSource: ProviderCookieSource? = switch request.provider {
        // Codex and Claude read local sign-ins; browser cookies only when the user picks the web source.
        case .codex, .claude: sourceMode == .web ? .auto : .off
        case .cursor, .opencode: .auto
        default: nil
        }
        let workspace = request.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderConfig(
            id: request.provider.coreProvider.instanceID,
            enabled: true,
            source: sourceMode,
            apiKey: request.secret,
            cookieSource: cookieSource,
            workspaceID: (workspace?.isEmpty ?? true) ? nil : workspace)
    }

    static func settingsSnapshot(
        for provider: ProviderID,
        config: ProviderConfig,
        env: [String: String]) -> ProviderSettingsSnapshot?
    {
        if provider == .codex {
            // Kazoo reads the live system Codex account only; CodexBar's managed-account store is not used.
            let reconciler = DefaultCodexAccountReconciler(
                storeLoader: { ManagedCodexAccountSet(version: 1, accounts: []) },
                activeSource: .liveSystem,
                baseEnvironment: env)
            let snapshot = reconciler.loadSnapshot()
            let resolved = CodexActiveSourceResolver.resolve(from: snapshot)
            let codex = CodexProviderSettingsBuilder.make(input: CodexProviderSettingsBuilderInput(
                usageDataSource: .auto,
                cookieSource: config.cookieSource ?? .off,
                manualCookieHeader: nil,
                reconciliationSnapshot: snapshot,
                resolvedActiveSource: resolved))
            return ProviderSettingsSnapshot.make(codex: codex)
        }
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider.coreProvider)
        guard let contribution = descriptor.settingsSection.credentialContribution(
            context: ProviderCredentialSettingsContext(config: config, account: nil))
        else { return nil }
        return ProviderSettingsSnapshot(contributions: [contribution])
    }
}
