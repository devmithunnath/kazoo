import AppKit
import Foundation

/// Runs `brew upgrade` for the Kazoo cask outside the app: the cask upgrade quits the running app, so the
/// upgrade happens in a detached helper that waits for Kazoo to exit, upgrades, and reopens it.
public enum BrewUpdater {
    public static var logURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Kazoo/update.log")
    }

    public static var manualCommand: String {
        "brew update && brew upgrade --cask \(InstallMethod.caskToken)"
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The helper script. Cleanup is disabled so updating Kazoo never removes unrelated Homebrew packages.
    public static func script(brewPath: String, appPath: String, pid: Int32, logPath: String) -> String {
        let brew = self.shellQuote(brewPath)
        let app = self.shellQuote(appPath)
        let log = self.shellQuote(logPath)
        return """
        #!/bin/zsh
        exec >>\(log) 2>&1
        echo "== Kazoo update started $(date)"
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        export HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_ANALYTICS=1
        \(brew) update --quiet || echo "brew update failed; trying the upgrade anyway"
        \(brew) upgrade --cask \(InstallMethod.caskToken)
        rc=$?
        echo "== brew upgrade exited with $rc"
        open \(app)
        exit $rc
        """
    }

    /// Writes and starts the helper detached from Kazoo. The caller should quit right after this returns.
    public static func start(brewPath: String, appPath: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dir = fm.temporaryDirectory.appendingPathComponent("Kazoo", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent("update-with-homebrew.sh")
        let body = self.script(brewPath: brewPath, appPath: appPath,
                               pid: ProcessInfo.processInfo.processIdentifier, logPath: self.logURL.path)
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/zsh")
        launcher.arguments = ["-c", "nohup /bin/zsh \(self.shellQuote(scriptURL.path)) >/dev/null 2>&1 &"]
        try launcher.run()
        launcher.waitUntilExit()
    }

    /// Last lines of the update log, for showing why an update didn't finish.
    public static func logTail(lines: Int = 6) -> String? {
        guard let text = try? String(contentsOf: self.logURL, encoding: .utf8) else { return nil }
        let tail = text.split(separator: "\n").suffix(lines).joined(separator: "\n")
        return tail.isEmpty ? nil : tail
    }
}
