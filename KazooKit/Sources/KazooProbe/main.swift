import Foundation
import KazooKit

// Usage: swift run kazoo-probe <provider> [source]
// Prints the normalized reading that the notch would display. Never prints credentials.
let args = CommandLine.arguments.dropFirst()
if args.first == "brew-script", args.count == 5 {
    // Usage: kazoo-probe brew-script <brew> <app> <pid> <log> — prints the exact helper script Kazoo runs.
    let a = Array(args)
    print(BrewUpdater.script(brewPath: a[1], appPath: a[2], pid: Int32(a[3]) ?? 0, logPath: a[4]))
    exit(0)
}
if args.first == "update" {
    // Usage: kazoo-probe update <current-version>
    let current = args.dropFirst().first ?? "0.0.0"
    let controller = await UpdateController(currentVersion: current, installMethod: .detect(),
                                            fetcher: GitHubReleaseFetcher(appVersion: current),
                                            defaults: UserDefaults(suiteName: "kazoo.probe") ?? .standard)
    await controller.check()
    print("current \(current) → \(await controller.status)")
    exit(0)
}
guard let raw = args.first, let provider = ProviderID(rawValue: raw) else {
    print("usage: kazoo-probe <\(ProviderID.allCases.map(\.rawValue).joined(separator: "|"))> [source]")
    exit(2)
}
CodexBarUsageSource.warmUp()
let secretEnv = ["copilot": "KAZOO_COPILOT_TOKEN", "openai": "KAZOO_OPENAI_ADMIN_KEY"][provider.rawValue]
let request = FetchRequest(
    provider: provider,
    secret: secretEnv.flatMap { ProcessInfo.processInfo.environment[$0] },
    workspaceID: ProcessInfo.processInfo.environment["KAZOO_WORKSPACE_ID"],
    sourceOverride: args.dropFirst().first)
do {
    let reading = try await CodexBarUsageSource().fetch(request)
    print("provider: \(reading.provider.displayName)  source: \(reading.sourceLabel)")
    print("identity: \(reading.identity?.summary == nil ? "none" : "present")")
    for meter in reading.meters {
        let reset = ResetFormatter.resetLine(for: meter) ?? ""
        print("  [\(meter.scope.rawValue)] \(meter.title): \(ValueFormatter.numeral(for: meter)) \(ValueFormatter.unit(for: meter))  \(reset)")
    }
    if let summary = reading.summaryMeter { print("collapsed: \(provider.shortName) | \(ValueFormatter.compact(for: summary))") }
    if !reading.spendHistory.isEmpty { print("history days: \(reading.spendHistory.count)") }
} catch {
    print("failure: \(error) → status: \(error.connectionStatus.label)")
    exit(1)
}
