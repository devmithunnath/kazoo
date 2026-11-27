import Foundation

/// User-visible connection state for one provider.
public enum ConnectionStatus: Sendable, Equatable {
    case notConnected
    case connecting
    case connected
    /// Signed in, but the provider did not return usage (e.g. a plan without quota data).
    case usageUnavailable(String)
    case expired
    case offline
    case failed(String)

    public var label: String {
        switch self {
        case .notConnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .usageUnavailable: "Signed in · usage unavailable"
        case .expired: "Sign-in expired"
        case .offline: "Offline"
        case .failed: "Couldn’t connect"
        }
    }

    public var detail: String? {
        switch self {
        case let .usageUnavailable(message), let .failed(message): message
        case .expired: "Sign in again to resume updates."
        case .offline: "Showing the last reading until the connection returns."
        default: nil
        }
    }

    public var isProblem: Bool {
        switch self {
        case .expired, .offline, .failed, .usageUnavailable: true
        default: false
        }
    }
}

/// A connected provider account. Stored in preferences; contains no secrets.
public struct ConnectedAccount: Codable, Sendable, Equatable {
    public var provider: ProviderID
    public var connectedAt: Date
    /// Optional workspace ID (OpenCode) entered by the user.
    public var workspaceID: String?
    /// Advanced source override; nil means the provider default.
    public var sourceOverride: String?
    /// Whether this account has an app-owned secret in Keychain (API key or device-flow token).
    public var hasStoredSecret: Bool
    /// The identity seen on the first successful reading, used to detect account switches.
    public var identityKey: String?

    public init(
        provider: ProviderID,
        connectedAt: Date = Date(),
        workspaceID: String? = nil,
        sourceOverride: String? = nil,
        hasStoredSecret: Bool = false,
        identityKey: String? = nil)
    {
        self.provider = provider
        self.connectedAt = connectedAt
        self.workspaceID = workspaceID
        self.sourceOverride = sourceOverride
        self.hasStoredSecret = hasStoredSecret
        self.identityKey = identityKey
    }
}
