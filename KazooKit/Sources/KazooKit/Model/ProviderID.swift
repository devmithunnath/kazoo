import Foundation

/// The seven providers Kazoo supports. App-owned so that views never depend on CodexBarCore types.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case codex
    case claude
    case cursor
    case copilot
    case gemini
    case opencode
    case openai

    public var id: String { self.rawValue }

    /// Full name used in detail headers, settings, and Connections.
    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        case .gemini: "Gemini CLI"
        case .opencode: "OpenCode"
        case .openai: "OpenAI API"
        }
    }

    /// Short name for the collapsed notch wing and overview columns.
    public var shortName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .copilot: "Copilot"
        case .gemini: "Gemini"
        case .opencode: "OpenCode"
        case .openai: "OpenAI"
        }
    }

    /// One line describing what is measured, shown in Connections.
    public var measures: String {
        switch self {
        case .codex: "ChatGPT subscription allowance for Codex (5-hour and weekly windows)."
        case .claude: "Claude subscription allowance (5-hour session, weekly, and model-specific windows)."
        case .cursor: "Included plan usage, billing cycle, and on-demand charges."
        case .copilot: "Premium request quota or AI credits used in the billing period."
        case .gemini: "Gemini CLI quota buckets (Pro, Flash) for the signed-in Google account."
        case .opencode: "Workspace spend, prepaid balance, or subscription quota windows."
        case .openai: "OpenAI API organization spend (requires an Admin key)."
        }
    }

    /// Extra terms that match in the Connections search field.
    public var searchKeywords: [String] {
        switch self {
        case .codex: ["openai", "chatgpt", "codex cli"]
        case .claude: ["anthropic", "claude code"]
        case .cursor: ["ide", "editor"]
        case .copilot: ["github", "microsoft"]
        case .gemini: ["google", "gemini cli"]
        case .opencode: ["zen", "workspace", "sst"]
        case .openai: ["api", "platform", "organization", "admin key", "spend"]
        }
    }

    public func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if self.displayName.lowercased().contains(q) { return true }
        return self.searchKeywords.contains { $0.contains(q) }
    }

    /// Providers whose collapsed summary is the lowest remaining account-wide window.
    public var summarizesLowestAccountWindow: Bool {
        self == .codex || self == .claude
    }
}
