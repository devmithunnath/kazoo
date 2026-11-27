import Foundation

/// How this copy of Kazoo was installed, which decides how it updates.
public enum InstallMethod: Sendable, Equatable {
    /// Installed with the Homebrew cask; updates run `brew upgrade` so Homebrew's records stay correct.
    case homebrew(brewPath: String)
    /// Downloaded or copied by hand.
    case manual
    /// Running from a build folder (Xcode, `dist/`); updates only link to the release.
    case development

    public static let caskToken = "devmithunnath/kazoo/kazoo"

    public var label: String {
        switch self {
        case .homebrew: "Homebrew"
        case .manual: "Direct download"
        case .development: "Development build"
        }
    }

    public static func detect(
        appPath: String = Bundle.main.bundleURL.path,
        home: String = NSHomeDirectory(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> InstallMethod
    {
        let applicationsPaths = ["/Applications/Kazoo.app", "\(home)/Applications/Kazoo.app"]
        guard applicationsPaths.contains(appPath) else { return .development }
        let caskrooms = [("/opt/homebrew/Caskroom/kazoo", "/opt/homebrew/bin/brew"),
                         ("/usr/local/Caskroom/kazoo", "/usr/local/bin/brew")]
        for (caskroom, brew) in caskrooms where fileExists(caskroom) && fileExists(brew) {
            return .homebrew(brewPath: brew)
        }
        return .manual
    }
}
