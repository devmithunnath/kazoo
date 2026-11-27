import AppKit
import CodexBarCore
import Foundation

/// GitHub device authorization for Copilot, using CodexBarCore's `CopilotDeviceFlow`.
public enum GitHubDeviceSignIn {
    public struct Code: Sendable, Equatable {
        public let userCode: String
        public let verificationURL: URL
    }

    /// Requests a device code, reports it, opens the browser, and polls until approved.
    /// Cancelling the calling task stops polling.
    public static func run(onCode: @escaping @MainActor (Code) -> Void) async throws(FetchFailure) -> String {
        let flow = CopilotDeviceFlow()
        do {
            let response = try await flow.requestDeviceCode()
            guard let url = URL(string: response.verificationURLToOpen) else { throw FetchFailure.other("Bad verification link.") }
            await MainActor.run {
                onCode(Code(userCode: response.userCode, verificationURL: url))
                NSWorkspace.shared.open(url)
            }
            return try await flow.pollForToken(
                deviceCode: response.deviceCode,
                interval: response.interval,
                expiresIn: response.expiresIn)
        } catch is CancellationError {
            throw .other("Cancelled")
        } catch let error as URLError where error.code == .userCancelledAuthentication {
            throw .notSignedIn("The GitHub authorization was denied.")
        } catch let error as URLError where error.code == .timedOut {
            throw .notSignedIn("The code expired before it was approved. Start again.")
        } catch {
            throw FailureClassifier.classify(error)
        }
    }
}
