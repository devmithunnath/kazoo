import AppKit
import CodexBarCore
import Foundation

/// A CLI that a provider relies on for its local sign-in.
public struct CompanionCLI: Sendable, Equatable {
    public let command: String
    public let displayName: String
    public let installURL: URL
    /// Arguments that start a browser sign-in non-interactively, or nil when the CLI only signs in interactively.
    public let browserLoginArguments: [String]?
    /// Whether the CLI prints the authorization link instead of opening the browser itself.
    public let opensLinkItself: Bool
    /// A desktop app that can serve the data instead of the CLI (e.g. Antigravity.app).
    public var appBundleID: String? = nil
    public var appName: String? = nil

    /// Whether the companion desktop app is installed.
    public var appURL: URL? {
        self.appBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    /// Resolves the CLI using the login-shell PATH and well-known install locations (CodexBar's `BinaryLocator`).
    public func resolve() -> String? {
        switch self.command {
        case "codex": BinaryLocator.resolveCodexBinary()
        case "claude": BinaryLocator.resolveClaudeBinary()
        case "gemini": BinaryLocator.resolveGeminiBinary()
        case "agy": BinaryLocator.resolveAntigravityBinary()
        default: nil
        }
    }
}

/// How a provider gets connected from the GUI.
public enum SetupKind: Sendable, Equatable {
    /// Reuse a sign-in that already exists on this Mac (with the user's permission).
    case localAccount(CompanionCLI)
    /// GitHub device authorization in the system browser.
    case deviceFlow
    /// Key-based provider: link to the key page and a secure input.
    case apiKey(keyURL: URL, requirement: String, placeholder: String)
    /// Reuse a browser session from a supported browser.
    case browserSession(signInURL: URL, asksForWorkspace: Bool)
}

public struct SetupGuide: Sendable, Equatable {
    public let provider: ProviderID
    /// The one concrete next action for a provider that is not yet connected.
    public let primaryAction: String
    public let kind: SetupKind
    /// What Kazoo will read, shown before the user grants permission.
    public let permissionNote: String
    public let docsURL: URL

    public static func guide(for provider: ProviderID) -> SetupGuide {
        switch provider {
        case .codex:
            SetupGuide(
                provider: .codex,
                primaryAction: "Use account on this Mac",
                kind: .localAccount(CompanionCLI(
                    command: "codex", displayName: "Codex CLI",
                    installURL: URL(string: "https://github.com/openai/codex#installing-and-running-codex-cli")!,
                    browserLoginArguments: ["login"], opensLinkItself: true)),
                permissionNote: "Kazoo will read the Codex sign-in already saved on this Mac (~/.codex) to fetch "
                    + "your ChatGPT plan’s Codex allowance. Nothing leaves this Mac except requests to OpenAI. "
                    + "This is separate from OpenAI API organization spend.",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/codex.md")!)
        case .claude:
            SetupGuide(
                provider: .claude,
                primaryAction: "Use account on this Mac",
                kind: .localAccount(CompanionCLI(
                    command: "claude", displayName: "Claude Code",
                    installURL: URL(string: "https://docs.anthropic.com/en/docs/claude-code/setup")!,
                    browserLoginArguments: ["auth", "login", "--claudeai"], opensLinkItself: false)),
                permissionNote: "Kazoo will reuse your Claude Code sign-in on this Mac. macOS may ask whether "
                    + "Kazoo can read the “Claude Code-credentials” Keychain item — choose Always Allow to avoid "
                    + "repeated prompts.",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/claude.md")!)
        case .cursor:
            SetupGuide(
                provider: .cursor,
                primaryAction: "Use browser sign-in",
                kind: .browserSession(signInURL: URL(string: "https://cursor.com/dashboard")!, asksForWorkspace: false),
                permissionNote: "Sign in at cursor.com in Safari, Chrome, Arc, Brave, Edge, or Firefox. Kazoo "
                    + "imports only the Cursor session cookie. macOS may ask for access to your browser’s "
                    + "Safe Storage key or Full Disk Access (for Safari).",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/cursor.md")!)
        case .copilot:
            SetupGuide(
                provider: .copilot,
                primaryAction: "Sign in with GitHub",
                kind: .deviceFlow,
                permissionNote: "GitHub will show a one-time code in your browser. Approve it to give Kazoo a token "
                    + "that can read your Copilot usage. The token is stored in your Keychain.",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/copilot.md")!)
        case .gemini:
            SetupGuide(
                provider: .gemini,
                primaryAction: "Use Gemini CLI sign-in",
                kind: .localAccount(CompanionCLI(
                    command: "gemini", displayName: "Gemini CLI",
                    installURL: URL(string: "https://github.com/google-gemini/gemini-cli#-installation")!,
                    browserLoginArguments: nil, opensLinkItself: true)),
                permissionNote: "Source: Gemini CLI. Kazoo reads the Google sign-in the Gemini CLI saved on this "
                    + "Mac (~/.gemini) and shows its per-model quota. The Gemini web app is not supported yet. "
                    + "Google individual, AI Pro, and Ultra accounts lost Gemini CLI sign-in in June 2026 — use "
                    + "Antigravity for those.",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/gemini.md")!)
        case .antigravity:
            SetupGuide(
                provider: .antigravity,
                primaryAction: "Use Antigravity on this Mac",
                kind: .localAccount(CompanionCLI(
                    command: "agy", displayName: "Antigravity CLI",
                    installURL: URL(string: "https://antigravity.google")!,
                    browserLoginArguments: nil, opensLinkItself: true,
                    appBundleID: "com.google.antigravity", appName: "Antigravity")),
                permissionNote: "Open the Antigravity app and sign in with Google, then connect. Kazoo reads quota "
                    + "from the app running on this Mac, or from the Antigravity CLI (agy) when the app is closed. "
                    + "Nothing is sent anywhere except Google’s own endpoints.",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/antigravity.md")!)
        case .opencode:
            SetupGuide(
                provider: .opencode,
                primaryAction: "Connect workspace",
                kind: .browserSession(signInURL: URL(string: "https://opencode.ai/auth")!, asksForWorkspace: true),
                permissionNote: "Sign in at opencode.ai in a supported browser. Kazoo imports the OpenCode session "
                    + "cookie and reads the workspace you choose (optional — leave blank for your default workspace).",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/opencode.md")!)
        case .openai:
            SetupGuide(
                provider: .openai,
                primaryAction: "Add admin key",
                kind: .apiKey(
                    keyURL: URL(string: "https://platform.openai.com/settings/organization/admin-keys")!,
                    requirement: "Organization spend needs an OpenAI Admin key (starts with sk-admin-). Only "
                        + "organization owners can create one. Project and service-account keys can’t read "
                        + "organization usage. The key is stored in your Keychain and used read-only.",
                    placeholder: "sk-admin-…"),
                permissionNote: "Kazoo calls OpenAI’s organization usage and costs endpoints with this key.",
                docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/openai.md")!)
        }
    }

    /// The recovery action label for a problem status.
    public func recoveryAction(for status: ConnectionStatus) -> String? {
        switch status {
        case .expired:
            switch self.kind {
            case .deviceFlow: "Sign in with GitHub again"
            case .apiKey: "Replace key"
            case .browserSession: "Check again"
            case let .localAccount(cli): cli.browserLoginArguments == nil ? "Check again" : "Sign in again"
            }
        case .failed where self.provider == .antigravity: "Open Antigravity"
        case .offline, .failed: "Try again"
        case .usageUnavailable: "Check again"
        default: nil
        }
    }
}
