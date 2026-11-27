import Foundation
import Testing
@testable import KazooKit

struct FakeReleases: ReleaseFetching {
    let result: Result<ReleaseInfo, UpdateCheckError>
    func latestRelease() async throws(UpdateCheckError) -> ReleaseInfo { try self.result.get() }
}

func release(_ version: String) -> ReleaseInfo {
    ReleaseInfo(version: version, tag: "v\(version)",
                pageURL: URL(string: "https://github.com/devmithunnath/kazoo/releases/tag/v\(version)")!,
                downloadURL: URL(string: "https://github.com/devmithunnath/kazoo/releases/download/v\(version)/Kazoo-\(version).zip")!,
                notes: nil, publishedAt: nil)
}

func freshDefaults() -> UserDefaults {
    let name = "kazoo.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Updates")
struct UpdateTests {
    @Test func versionComparison() {
        #expect(AppVersion("v0.1.1")! > AppVersion("0.1.0")!)
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
        #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
        #expect(AppVersion("1.2.0-beta")! == AppVersion("1.2.0")!)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test func parsesGitHubRelease() throws {
        let json = #"""
        {"tag_name":"v0.1.1","html_url":"https://github.com/devmithunnath/kazoo/releases/tag/v0.1.1",
         "body":"","draft":false,"prerelease":false,"published_at":"2026-11-27T05:12:11Z",
         "assets":[{"name":"Kazoo-0.1.1.zip","browser_download_url":"https://github.com/devmithunnath/kazoo/releases/download/v0.1.1/Kazoo-0.1.1.zip"}]}
        """#
        let info = try GitHubReleaseFetcher.parse(Data(json.utf8))
        #expect(info.version == "0.1.1")
        #expect(info.downloadURL?.lastPathComponent == "Kazoo-0.1.1.zip")
        #expect(info.notes == nil)
        let prerelease = json.replacingOccurrences(of: #""prerelease":false"#, with: #""prerelease":true"#)
        #expect(throws: UpdateCheckError.invalidResponse) { try GitHubReleaseFetcher.parse(Data(prerelease.utf8)) }
    }

    @Test func detectsInstallMethod() {
        let home = "/Users/me"
        let brewFiles: Set<String> = ["/opt/homebrew/Caskroom/kazoo", "/opt/homebrew/bin/brew"]
        #expect(InstallMethod.detect(appPath: "/Applications/Kazoo.app", home: home, fileExists: brewFiles.contains)
            == .homebrew(brewPath: "/opt/homebrew/bin/brew"))
        let intelFiles: Set<String> = ["/usr/local/Caskroom/kazoo", "/usr/local/bin/brew"]
        #expect(InstallMethod.detect(appPath: "/Applications/Kazoo.app", home: home, fileExists: intelFiles.contains)
            == .homebrew(brewPath: "/usr/local/bin/brew"))
        #expect(InstallMethod.detect(appPath: "/Applications/Kazoo.app", home: home, fileExists: { _ in false }) == .manual)
        // A Caskroom record without brew itself can't run an upgrade.
        #expect(InstallMethod.detect(appPath: "/Applications/Kazoo.app", home: home,
                                     fileExists: { $0 == "/opt/homebrew/Caskroom/kazoo" }) == .manual)
        #expect(InstallMethod.detect(appPath: "/Users/me/src/kazoo/dist/Kazoo.app", home: home,
                                     fileExists: brewFiles.contains) == .development)
    }

    @Test func brewScriptIsSafe() {
        let script = BrewUpdater.script(brewPath: "/opt/homebrew/bin/brew", appPath: "/Applications/Kazoo.app",
                                        pid: 4242, logPath: "/Users/me/Library/Logs/Kazoo/update.log")
        #expect(script.contains("while kill -0 4242"))
        #expect(script.contains("'/opt/homebrew/bin/brew' upgrade --cask devmithunnath/kazoo/kazoo"))
        #expect(script.contains("HOMEBREW_NO_INSTALL_CLEANUP=1")) // never remove unrelated packages
        #expect(script.contains("open '/Applications/Kazoo.app'"))
        #expect(BrewUpdater.shellQuote("it's") == #"'it'\''s'"#)
    }

    @MainActor @Test func findsNewerReleaseAndUpdatesWithHomebrew() async {
        let controller = UpdateController(
            currentVersion: "0.1.1", installMethod: .homebrew(brewPath: "/opt/homebrew/bin/brew"),
            fetcher: FakeReleases(result: .success(release("0.1.2"))), defaults: freshDefaults())
        var started: (String, String)?
        var quit = false
        controller.startBrewUpdate = { started = ($0, $1) }
        controller.quitForUpdate = { quit = true }
        await controller.check()
        #expect(controller.availableRelease?.version == "0.1.2")
        controller.install()
        #expect(started?.0 == "/opt/homebrew/bin/brew")
        #expect(controller.status == .installing)
        try? await Task.sleep(nanoseconds: 900_000_000)
        #expect(quit)
    }

    @MainActor @Test func upToDateAndManualDownload() async {
        let same = UpdateController(currentVersion: "0.1.1", installMethod: .manual,
                                    fetcher: FakeReleases(result: .success(release("0.1.1"))), defaults: freshDefaults())
        await same.check()
        #expect(same.status == .upToDate)

        let manual = UpdateController(currentVersion: "0.1.0", installMethod: .manual,
                                      fetcher: FakeReleases(result: .success(release("0.1.1"))), defaults: freshDefaults())
        var opened: URL?
        manual.openURL = { opened = $0 }
        await manual.check()
        manual.install()
        #expect(opened?.lastPathComponent == "Kazoo-0.1.1.zip")
    }

    @MainActor @Test func automaticChecksAreQuietAndThrottled() async {
        let defaults = freshDefaults()
        let offline = UpdateController(currentVersion: "0.1.1", installMethod: .manual,
                                       fetcher: FakeReleases(result: .failure(.offline)), defaults: defaults)
        await offline.check(automatic: true)
        #expect(offline.status == .idle) // automatic failures stay quiet
        await offline.check()
        #expect(offline.status == .failed(UpdateCheckError.offline.errorDescription!))

        defaults.set(Date(), forKey: UpdateController.Keys.lastChecked)
        let recent = UpdateController(currentVersion: "0.1.0", installMethod: .manual,
                                      fetcher: FakeReleases(result: .success(release("0.1.1"))), defaults: defaults)
        await recent.check(automatic: true)
        #expect(recent.status == .idle) // checked moments ago: skipped
        await recent.check()
        #expect(recent.availableRelease != nil) // manual checks always run
    }

    @MainActor @Test func reportsResultAfterHomebrewRelaunch() {
        let defaults = freshDefaults()
        defaults.set(["from": "0.1.1", "to": "0.1.2", "started": Date().timeIntervalSince1970] as [String: Any],
                     forKey: UpdateController.Keys.pending)
        let updated = UpdateController(currentVersion: "0.1.2", installMethod: .manual,
                                       fetcher: FakeReleases(result: .failure(.offline)), defaults: defaults)
        #expect(updated.status == .updated("0.1.2"))

        defaults.set(["from": "0.1.1", "to": "0.1.2", "started": Date().timeIntervalSince1970] as [String: Any],
                     forKey: UpdateController.Keys.pending)
        let failed = UpdateController(currentVersion: "0.1.1", installMethod: .manual,
                                      fetcher: FakeReleases(result: .failure(.offline)), defaults: defaults)
        #expect(failed.status == .updateFailed("Homebrew didn’t finish updating to 0.1.2."))
        #expect(defaults.dictionary(forKey: UpdateController.Keys.pending) == nil)
    }
}
