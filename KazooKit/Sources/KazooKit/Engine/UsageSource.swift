import Foundation

/// Everything a usage source needs to fetch one provider account. Secrets are passed in, never logged.
public struct FetchRequest: Sendable {
    public var provider: ProviderID
    /// App-owned secret from Keychain (API key or device-flow token), if any.
    public var secret: String?
    public var workspaceID: String?
    public var sourceOverride: String?
    /// True when the user clicked something (connect, check again, refresh). Only then may the provider engine
    /// show macOS permission prompts such as Keychain access; automatic refreshes stay silent.
    public var interactive: Bool

    public init(
        provider: ProviderID,
        secret: String? = nil,
        workspaceID: String? = nil,
        sourceOverride: String? = nil,
        interactive: Bool = false)
    {
        self.provider = provider
        self.secret = secret
        self.workspaceID = workspaceID
        self.sourceOverride = sourceOverride
        self.interactive = interactive
    }
}

/// Classified fetch failure. Drives the connection status and recovery action.
public enum FetchFailure: Error, Sendable, Equatable, LocalizedError {
    /// No local sign-in or credential was found.
    case notSignedIn(String)
    /// Credentials exist but were rejected or have expired.
    case expired(String)
    case offline
    case rateLimited(retryAfter: TimeInterval?)
    /// Signed in but the provider returned no usage for this account.
    case usageUnavailable(String)
    /// macOS needs the user's permission (e.g. Keychain access) before the sign-in can be read.
    case needsPermission(String)
    case other(String)

    public var errorDescription: String? {
        switch self {
        case let .notSignedIn(m), let .expired(m), let .usageUnavailable(m), let .needsPermission(m), let .other(m): m
        case .offline: "The network is unavailable."
        case .rateLimited: "The provider is rate-limiting requests. Kazoo will retry later."
        }
    }

    /// Whether a cached reading should be kept (transient) rather than cleared.
    public var isTransient: Bool {
        switch self {
        case .offline, .rateLimited, .other: true
        case .notSignedIn, .expired, .usageUnavailable, .needsPermission: false
        }
    }

    public var connectionStatus: ConnectionStatus {
        switch self {
        case .notSignedIn: .failed(self.errorDescription ?? "Not signed in")
        case .expired: .expired
        case .offline: .offline
        case .rateLimited: .connected
        case let .usageUnavailable(m): .usageUnavailable(m)
        case let .needsPermission(m): .failed(m)
        case let .other(m): .failed(m)
        }
    }
}

/// The single app-owned interface every provider adapter sits behind.
public protocol UsageSource: Sendable {
    func fetch(_ request: FetchRequest) async throws(FetchFailure) -> UsageReading
}

/// Maps arbitrary upstream errors to `FetchFailure`. Conservative: only explicit signals count as auth failures.
public enum FailureClassifier {
    public static let permissionMessage = "macOS needs your permission to read this sign-in from the Keychain. "
        + "Click Check again and choose Always Allow in the Keychain prompt."

    public static func classify(_ error: Error) -> FetchFailure {
        if let failure = error as? FetchFailure { return failure }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
                return .offline
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return .expired("The provider rejected the saved sign-in.")
            default:
                break
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorNotConnectedToInternet { return .offline }
        return self.classify(message: error.localizedDescription)
    }

    public static func classify(message raw: String) -> FetchFailure {
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = message.lowercased()
        if m.contains("re-grant") || m.contains("credentials changed") || m.contains("currently unavailable to")
            || m.contains("keychain access") || m.contains("errsecusercanceled") || m.contains("user canceled")
        {
            return .needsPermission(Self.permissionMessage)
        }
        if m.contains("429") || m.contains("rate limit") || m.contains("rate-limit") || m.contains("too many requests") {
            return .rateLimited(retryAfter: nil)
        }
        if m.contains("offline") || m.contains("not connected to the internet") || m.contains("network connection") {
            return .offline
        }
        if m.contains("expired") || m.contains("401") || m.contains("unauthorized") || m.contains("invalid_grant")
            || m.contains("re-authenticate") || m.contains("reauthenticate") || m.contains("sign in again")
        {
            return .expired(message.isEmpty ? "Sign-in expired." : message)
        }
        if m.contains("not logged in") || m.contains("not signed in") || m.contains("no credentials")
            || m.contains("missing credentials") || m.contains("no session") || m.contains("credentials not found")
            || m.contains("auth.json") || m.contains("no available fetch strategy") || m.contains("no cookies")
            || m.contains("api key") && m.contains("missing")
        {
            return .notSignedIn(message.isEmpty ? "No sign-in found." : message)
        }
        if m.contains("no usage") || m.contains("usage unavailable") || m.contains("subscription ended")
            || m.contains("subscriptionended")
        {
            return .usageUnavailable(message)
        }
        return .other(message.isEmpty ? "Unknown error" : message)
    }
}
