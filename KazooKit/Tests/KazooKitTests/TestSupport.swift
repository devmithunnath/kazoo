import Foundation
@testable import KazooKit

/// Scripted usage source. Each provider gets a queue of results; an optional gate holds requests in flight.
actor ScriptedSource: UsageSource {
    private var queues: [ProviderID: [Result<UsageReading, FetchFailure>]] = [:]
    private(set) var calls: [ProviderID: Int] = [:]
    private(set) var interactiveFlags: [Bool] = []
    private var gated = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enqueue(_ provider: ProviderID, _ results: Result<UsageReading, FetchFailure>...) {
        self.queues[provider, default: []].append(contentsOf: results)
    }

    func setGate(_ on: Bool) {
        self.gated = on
        if !on {
            let pending = self.waiters
            self.waiters = []
            pending.forEach { $0.resume() }
        }
    }

    func callCount(_ provider: ProviderID) -> Int { self.calls[provider] ?? 0 }

    func fetch(_ request: FetchRequest) async throws(FetchFailure) -> UsageReading {
        self.calls[request.provider, default: 0] += 1
        self.interactiveFlags.append(request.interactive)
        if self.gated {
            await withCheckedContinuation { self.waiters.append($0) }
        }
        var queue = self.queues[request.provider] ?? []
        let next = queue.isEmpty ? .failure(.other("no scripted result")) : queue.removeFirst()
        self.queues[request.provider] = queue
        return try next.get()
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { self.now = self.now.addingTimeInterval(seconds) }
}

enum Make {
    static func percentReading(
        _ provider: ProviderID,
        _ values: [(String, Double, MeterScope)],
        email: String = "a@example.com",
        resetsAt: Date? = nil,
        fetchedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> UsageReading
    {
        UsageReading(
            provider: provider,
            meters: values.map { Meter(id: $0.0, title: $0.0, shortTitle: $0.0, value: .remainingPercent($0.1),
                                       scope: $0.2, resetsAt: resetsAt) },
            identity: AccountIdentity(email: email),
            sourceLabel: "test",
            fetchedAt: fetchedAt)
    }
}

@MainActor
func makeStore(
    source: ScriptedSource,
    prefs: AppPreferences = AppPreferences(),
    clock: TestClock = TestClock(),
    cache: MemoryReadingCache = MemoryReadingCache(),
    secrets: MemorySecretStore = MemorySecretStore()) -> UsageStore
{
    UsageStore(
        liveSource: source,
        secrets: secrets,
        preferences: MemoryPreferences(prefs),
        cache: cache,
        clock: { clock.now })
}
