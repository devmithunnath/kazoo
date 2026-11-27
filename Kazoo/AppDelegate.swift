import AppKit
import KazooKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var store: UsageStore!

    private static func argumentValue(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    private let router = PanelRouter()
    private var windows: WindowCoordinator!
    private var notch: NotchController!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        CodexBarUsageSource.warmUp()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo") {
            // Isolated, in-memory demo session (screenshots, QA): never touches saved accounts or Keychain.
            var prefs = AppPreferences()
            prefs.demoMode = true
            if let favorite = Self.argumentValue("--favorite").flatMap(ProviderID.init(rawValue:)) {
                prefs.favorite = favorite
            }
            if let pinned = Self.argumentValue("--pinned") {
                prefs.pinned = pinned.split(separator: ",").compactMap { ProviderID(rawValue: String($0)) }
            }
            self.store = UsageStore(
                liveSource: DemoUsageSource(),
                secrets: MemorySecretStore(),
                preferences: MemoryPreferences(prefs),
                cache: MemoryReadingCache())
        } else {
            let secrets = KeychainSecretStore()
            LegacyMigration.runIfNeeded(secrets: secrets)
            self.store = UsageStore(
                liveSource: CodexBarUsageSource(),
                secrets: secrets,
                preferences: UserDefaultsPreferences(),
                cache: FileReadingCache())
        }

        self.windows = WindowCoordinator(store: self.store)
        let actions = PanelActions(
            openConnections: { [weak self] provider in
                self?.dismissPanels()
                self?.windows.showConnections(provider: provider)
            },
            openSettings: { [weak self] in
                self?.dismissPanels()
                self?.windows.showSettings()
            },
            dismiss: { [weak self] in self?.dismissPanels() })
        let menu: () -> NSMenu = { [weak self] in self?.contextMenu() ?? NSMenu() }
        self.notch = NotchController(store: self.store, router: self.router, actions: actions, menuProvider: menu)
        self.statusItem = StatusItemController(store: self.store, router: self.router, actions: actions, menuProvider: menu)
        self.installMainMenu()
        self.evaluatePlacement()

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in self?.evaluatePlacement() }
        }
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.evaluatePlacement() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePlacement()
                // Give the network a moment to come back before refreshing.
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self?.store.refreshAll(manual: false)
            }
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in self?.dismissPanels() }
        }

        self.store.startAutoRefresh()
        if arguments.contains("--open-panel") {
            // QA: open the expanded panel at launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.notch.expand() }
        } else if !self.store.hasConnections {
            self.windows.showConnections()
        }
    }

    /// Notch on a display with a camera housing; menu-bar item when there is none, when the notched display is not
    /// the primary display, or when the user asked for it.
    private func evaluatePlacement() {
        let notched = NotchGeometry.notchedScreen()
        self.notch.apply(geometry: notched?.1)
        let notchIsPrimary = notched.map { $0.0 == NSScreen.screens.first } ?? false
        let showStatusItem = notched == nil || !notchIsPrimary || self.store.preferences.showMenuBarItemAlways
        self.statusItem.setVisible(showStatusItem)
    }

    private func dismissPanels() {
        self.notch.collapse()
        self.statusItem.close()
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh", action: #selector(self.menuRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let connections = NSMenuItem(title: "Connections…", action: #selector(self.menuConnections), keyEquivalent: "")
        connections.target = self
        menu.addItem(connections)
        let settings = NSMenuItem(title: "Settings…", action: #selector(self.menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(self.store.preferences.displayName)",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func menuRefresh() { self.store.refreshAll(manual: true) }
    @objc private func menuConnections() { self.windows.showConnections() }
    @objc private func menuSettings() { self.windows.showSettings() }

    /// Minimal main menu so standard editing shortcuts (⌘V into the key field, ⌘W, ⌘Q) work in windows.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(self.menuSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        self.windows.showConnections()
        return true
    }
}
