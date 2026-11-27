// Browser-waiting CLI login runner. Adapted from CodexBar's `CLILoginRunner` / `ClaudeLoginRunner`
// (MIT, © Peter Steinberger): bounded output capture, timeout, cancellation that terminates the child process,
// and authorization-link extraction. Simplified to a pseudo-terminal via /usr/bin/script.
import AppKit
import CodexBarCore
import Foundation

public enum LoginRunOutcome: Sendable, Equatable {
    case success
    case cancelled
    case timedOut
    case failed(String)
    case missingBinary
}

public enum LoginRunner {
    /// Runs `<binary> <arguments>` in a pseudo-terminal and waits for it to exit.
    /// Opens the first https link the CLI prints when `openLink` is true. Cancelling the task terminates the CLI.
    public static func run(
        binary: String,
        arguments: [String],
        openLink: Bool,
        timeout: TimeInterval = 300) async -> LoginRunOutcome
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", binary] + arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = PathBuilder.effectivePATH(purposes: [.tty, .nodeTooling], env: env)
        env["BROWSER"] = nil
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        let buffer = OutputBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            if let link = buffer.append(text), openLink, let url = URL(string: link) {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<LoginRunOutcome, Never>) in
                let once = OnceFlag()
                process.terminationHandler = { proc in
                    output.fileHandleForReading.readabilityHandler = nil
                    guard once.claim() else { return }
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(returning: .cancelled)
                    } else if proc.terminationStatus == 0 {
                        continuation.resume(returning: .success)
                    } else {
                        continuation.resume(returning: .failed(buffer.tail()))
                    }
                }
                do {
                    try process.run()
                } catch {
                    if once.claim() { continuation.resume(returning: .failed(error.localizedDescription)) }
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning, once.claim() else { return }
                    process.terminate()
                    continuation.resume(returning: .timedOut)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Opens Terminal running an interactive CLI sign-in (for CLIs without a non-interactive login),
    /// so the user never has to type a command.
    @MainActor
    public static func openInteractiveSignIn(binary: String, title: String) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Kazoo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("\(title.replacingOccurrences(of: " ", with: "-"))-sign-in.command")
        let escaped = binary.replacingOccurrences(of: "'", with: "'\\''")
        let body = """
        #!/bin/zsh -l
        clear
        echo "Kazoo: complete the \(title) sign-in in this window, then return to Kazoo and click Check again."
        echo
        exec '\(escaped)'
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private var text = ""
    private var linkFound = false
    private let lock = NSLock()
    private let limit = 16_000

    /// Appends output and returns the first authorization link the first time one appears.
    func append(_ chunk: String) -> String? {
        self.lock.withLock {
            self.text += chunk
            if self.text.count > self.limit { self.text = String(self.text.suffix(self.limit)) }
            guard !self.linkFound,
                  let range = self.text.range(of: #"https://[^\s\u{1B}"'<>]+"#, options: .regularExpression)
            else { return nil }
            self.linkFound = true
            return String(self.text[range])
        }
    }

    func tail() -> String {
        self.lock.withLock {
            let cleaned = self.text.replacingOccurrences(of: #"\u{1B}\[[0-9;?]*[A-Za-z]"#, with: "",
                                                          options: .regularExpression)
            return String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private var claimed = false
    private let lock = NSLock()
    func claim() -> Bool {
        self.lock.withLock {
            if self.claimed { return false }
            self.claimed = true
            return true
        }
    }
}
