import AppKit
import Foundation

/// Drives one provider's connect / verify / recover flow in the Connections window.
@MainActor
public final class ConnectFlowModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case verifying
        /// Local sign-in missing or expired: offer the companion CLI route.
        case needsCompanion(String)
        case signingIn
        case waitingForInteractiveSignIn
        case deviceCode(GitHubDeviceSignIn.Code)
        case done
        case failed(String)
    }

    @Published public var phase: Phase = .idle
    @Published public var apiKey = ""
    @Published public var workspaceID: String
    @Published public var sourceOverride: String
    @Published public private(set) var companionPath: String?

    public let provider: ProviderID
    public let guide: SetupGuide
    private let store: UsageStore
    private var task: Task<Void, Never>?

    public init(provider: ProviderID, store: UsageStore) {
        self.provider = provider
        self.store = store
        self.guide = SetupGuide.guide(for: provider)
        self.workspaceID = store.account(for: provider)?.workspaceID ?? ""
        self.sourceOverride = store.account(for: provider)?.sourceOverride ?? "auto"
        self.detectCompanion()
    }

    public var isBusy: Bool {
        switch self.phase {
        case .verifying, .signingIn, .deviceCode: true
        default: false
        }
    }

    public var companion: CompanionCLI? {
        if case let .localAccount(cli) = self.guide.kind { return cli }
        return nil
    }

    public func detectCompanion() {
        guard let cli = self.companion else { return }
        Task.detached(priority: .userInitiated) {
            let path = cli.resolve()
            await MainActor.run { self.companionPath = path }
        }
    }

    /// The row's one concrete next action.
    public func primary() {
        switch self.guide.kind {
        case .deviceFlow:
            self.startDeviceFlow()
        case .apiKey:
            let key = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                // Re-check an existing connection with the key already in Keychain.
                guard self.store.account(for: self.provider)?.hasStoredSecret == true else {
                    self.phase = .failed("Paste a key first.")
                    return
                }
                self.verify(secret: nil)
            } else {
                self.verify(secret: key)
            }
        case .localAccount, .browserSession:
            self.verify(secret: nil)
        }
    }

    public func verify(secret: String?) {
        self.task?.cancel()
        self.phase = .verifying
        let source = self.provider.advancedSourceChoices.isEmpty || self.sourceOverride == "auto" ? nil : self.sourceOverride
        let workspace = self.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.task = Task {
            let result = await self.store.connect(
                self.provider, secret: secret,
                workspaceID: workspace.isEmpty ? nil : workspace,
                sourceOverride: source)
            guard !Task.isCancelled else { return }
            switch result {
            case .success:
                self.apiKey = ""
                self.phase = .done
            case let .failure(failure):
                switch (self.guide.kind, failure) {
                case (.localAccount, .companionNotRunning(let message)):
                    self.detectCompanion()
                    self.phase = .needsCompanion(message)
                case (_, .needsPermission(let message)):
                    self.phase = .failed(message)
                case (_, .usageUnavailable):
                    self.phase = .done
                case (.localAccount(let cli), .notSignedIn):
                    self.detectCompanion()
                    self.phase = .needsCompanion("No \(cli.displayName) sign-in was found on this Mac.")
                case (.localAccount(let cli), .expired):
                    self.detectCompanion()
                    self.phase = .needsCompanion("Your \(cli.displayName) sign-in has expired. Sign in again to continue.")
                case (.browserSession, .notSignedIn):
                    self.phase = .failed("No \(self.provider.displayName) browser session was found. Sign in on the "
                        + "website in a supported browser, then click Check again.")
                default:
                    self.phase = .failed(failure.errorDescription ?? "Couldn’t connect.")
                }
            }
        }
    }

    /// Signs in through the companion CLI without the user typing a command.
    public func signInWithCompanion() {
        guard let cli = self.companion else { return }
        guard let path = self.companionPath ?? cli.resolve() else {
            self.phase = .needsCompanion("\(cli.displayName) isn’t installed.")
            return
        }
        guard let arguments = cli.browserLoginArguments else {
            do {
                try LoginRunner.openInteractiveSignIn(binary: path, title: cli.displayName)
                self.phase = .waitingForInteractiveSignIn
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
            return
        }
        self.phase = .signingIn
        self.task = Task {
            let outcome = await LoginRunner.run(binary: path, arguments: arguments, openLink: !cli.opensLinkItself)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success: self.verify(secret: nil)
            case .cancelled: self.phase = .idle
            case .timedOut: self.phase = .failed("The browser sign-in timed out. Try again.")
            case .missingBinary: self.phase = .needsCompanion("\(cli.displayName) isn’t installed.")
            case let .failed(message): self.phase = .failed("Sign-in didn’t finish. \(message)")
            }
        }
    }

    private func startDeviceFlow() {
        self.task?.cancel()
        self.phase = .verifying
        self.task = Task {
            do {
                let token = try await GitHubDeviceSignIn.run { code in
                    self.phase = .deviceCode(code)
                }
                guard !Task.isCancelled else { return }
                self.verify(secret: token)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed((error as? FetchFailure)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Opens the companion desktop app (e.g. Antigravity), then re-checks after it has had time to start.
    public func openCompanionApp() {
        guard let url = self.companion?.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        self.phase = .verifying
        self.task?.cancel()
        self.task = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self.verify(secret: nil)
        }
    }

    public func cancel() {
        self.task?.cancel()
        self.task = nil
        self.store.cancelConnect(self.provider)
        self.phase = .idle
    }

    public func copyAntigravityInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CodexBarUsageSource.antigravityCLIInstallCommand, forType: .string)
    }

    public func copyDeviceCode() {
        guard case let .deviceCode(code) = self.phase else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
    }
}
