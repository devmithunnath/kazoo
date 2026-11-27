import Foundation
import KazooKit

// Usage: swift run kazoo-probe <provider> [source]
// Prints the normalized reading that the notch would display. Never prints credentials.
let args = CommandLine.arguments.dropFirst()
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
