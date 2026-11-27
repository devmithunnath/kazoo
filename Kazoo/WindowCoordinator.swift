import AppKit
import KazooKit
import SwiftUI

@MainActor
final class ConnectionsSelection: ObservableObject {
    @Published var provider: ProviderID?
}

private struct ConnectionsHost: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var selection: ConnectionsSelection
    var body: some View {
        ConnectionsView(store: self.store, selection: self.$selection.provider)
    }
}

/// Owns the native Connections and Settings windows. Kazoo becomes a regular app (Dock + ⌘-Tab) only while
/// one of these windows is open.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let selection = ConnectionsSelection()
    private var connectionsWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private let updates: UpdateController

    init(store: UsageStore, updates: UpdateController) {
        self.store = store
        self.updates = updates
    }

    func showConnections(provider: ProviderID? = nil) {
        if let provider { self.selection.provider = provider }
        if self.connectionsWindow == nil {
            let controller = NSHostingController(rootView: ConnectionsHost(store: self.store, selection: self.selection))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 860, height: 580))
            window.setFrameAutosaveName("KazooConnections")
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.connectionsWindow = window
        }
        self.connectionsWindow?.title = "Connections — \(self.store.preferences.displayName)"
        self.present(self.connectionsWindow)
    }

    func showSettings() {
        if self.settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(store: self.store, updates: self.updates) { [weak self] in
                self?.showConnections()
            })
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 640))
            window.setFrameAutosaveName("KazooSettings")
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.settingsWindow = window
        }
        self.settingsWindow?.title = "\(self.store.preferences.displayName) Settings"
        self.present(self.settingsWindow)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let anyVisible = [self.connectionsWindow, self.settingsWindow].contains { $0?.isVisible == true }
            if !anyVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
