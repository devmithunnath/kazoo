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
        let provider = request.provider.coreProvider
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let sourceMode = request.sourceOverride.flatMap(ProviderSourceMode.init(rawValue:))
            ?? request.provider.defaultSourceMode
        guard descriptor.fetchPlan.sourceModes.contains(sourceMode) else {
            throw .other("\(request.provider.displayName) does not support the “\(sourceMode.rawValue)” source.")
        }
        if request.provider == .copilot || request.provider == .openai {
            guard let secret = request.secret, !secret.isEmpty else {
                throw .notSignedIn("No saved credential for \(request.provider.displayName).")
            }
        }

        let baseEnv = Self.baseEnvironment()
        let config = Self.providerConfig(for: request, sourceMode: sourceMode)
        let env = ProviderEnvironmentResolver.resolve(
            base: baseEnv,
            provider: provider,
            config: config,
            selectedAccount: nil)
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

        // CodexBarCore only shows Keychain/permission prompts for user-initiated fetches.
        let interaction: ProviderInteraction = request.interactive ? .userInitiated : .background
        let outcome = await ProviderInteractionContext.$current.withValue(interaction) {
            await descriptor.fetchOutcome(context: context)
        }
        switch outcome.result {
        case let .success(result):
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
