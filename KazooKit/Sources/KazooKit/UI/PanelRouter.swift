import SwiftUI

public enum PanelRoute: Hashable, Sendable {
    case empty
    case overview
    case allProviders
    case detail(ProviderID)
}

/// Navigation inside the notch panel. One connected provider opens its detail directly;
/// several open the pinned overview.
@MainActor
public final class PanelRouter: ObservableObject {
    @Published public private(set) var stack: [PanelRoute] = [.overview]

    public init() {}

    public var current: PanelRoute { self.stack.last ?? .overview }
    public var canGoBack: Bool { self.stack.count > 1 }

    public func reset(for store: UsageStore) {
        let connected = store.connectedProviders
        if connected.isEmpty {
            self.stack = [.empty]
        } else if connected.count == 1 {
            self.stack = [.detail(connected[0])]
        } else {
            self.stack = [.overview]
        }
    }

    public func push(_ route: PanelRoute) {
        guard route != self.current else { return }
        self.stack.append(route)
    }

    public func back() {
        guard self.canGoBack else { return }
        self.stack.removeLast()
    }

    /// Title for the back button ("Providers" in the references).
    public var backTitle: String {
        guard self.stack.count > 1 else { return "" }
        switch self.stack[self.stack.count - 2] {
        case .overview: return "Providers"
        case .allProviders: return "All providers"
        default: return "Back"
        }
    }
}

/// Callbacks the AppKit host supplies to the SwiftUI panel.
public struct PanelActions {
    public var openConnections: (ProviderID?) -> Void
    public var openSettings: () -> Void
    public var dismiss: () -> Void

    public init(
        openConnections: @escaping (ProviderID?) -> Void = { _ in },
        openSettings: @escaping () -> Void = {},
        dismiss: @escaping () -> Void = {})
    {
        self.openConnections = openConnections
        self.openSettings = openSettings
        self.dismiss = dismiss
    }
}
