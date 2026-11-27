import AppKit
import Combine
import KazooKit
import SwiftUI

/// A borderless panel that never activates Kazoo, so the user's foreground app keeps focus
/// until they deliberately interact with it.
final class NotchPanel: NSPanel {
    var allowsKey = false
    var onEscape: (() -> Void)?

    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.isFloatingPanel = true
        self.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .none
    }

    override var canBecomeKey: Bool { self.allowsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        self.onEscape?()
    }
}

/// Transparent overlay that turns clicks on the collapsed notch into open / context-menu actions.
final class ClickCatcherView: NSView {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    override func mouseDown(with event: NSEvent) { self.onClick?() }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = self.menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool {
        self.onClick?()
        return true
    }
}

@MainActor
final class NotchController {
    private let store: UsageStore
    private let router: PanelRouter
    private let actions: PanelActions
    private let menuProvider: () -> NSMenu

    private var geometry: NotchGeometry?
    private var collapsed: NotchPanel?
    private var collapsedHost: NSHostingView<CollapsedNotchView>?
    private var catcher: ClickCatcherView?
    private var expanded: NotchPanel?
    private var expandedHost: NSHostingView<NotchHostedPanel>?
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var wingWidth: CGFloat = 0

    private(set) var isExpanded = false

    init(store: UsageStore, router: PanelRouter, actions: PanelActions, menuProvider: @escaping () -> NSMenu) {
        self.store = store
        self.router = router
        self.actions = actions
        self.menuProvider = menuProvider

        store.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.layoutCollapsed()
                self?.resizeExpanded(animated: true)
            }
            .store(in: &self.cancellables)
        router.$stack
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizeExpanded(animated: true) }
            }
            .store(in: &self.cancellables)
    }

    /// Shows the notch UI on `geometry`, or tears it down when nil.
    func apply(geometry: NotchGeometry?) {
        self.geometry = geometry
        guard geometry != nil else {
            self.collapse()
            self.collapsed?.orderOut(nil)
            return
        }
        if self.collapsed == nil { self.buildCollapsed() }
        self.layoutCollapsed()
        if !self.isExpanded { self.collapsed?.orderFrontRegardless() }
    }

    // MARK: Collapsed

    private func buildCollapsed() {
        let panel = NotchPanel(contentRect: .zero)
        panel.allowsKey = false
        let host = NSHostingView(rootView: CollapsedNotchView(store: self.store, notchWidth: 0, wingWidth: 0, height: 32))
        let container = NSView()
        container.addSubview(host)
        let catcher = ClickCatcherView()
        catcher.setAccessibilityLabel("AI usage")
        catcher.onClick = { [weak self] in self?.toggle() }
        catcher.menuProvider = self.menuProvider
        container.addSubview(catcher)
        panel.contentView = container
        self.collapsed = panel
        self.collapsedHost = host
        self.catcher = catcher
    }

    private func layoutCollapsed() {
        guard let geometry, let panel = self.collapsed, let host = self.collapsedHost else { return }
        let wing = self.measureWing()
        let height = geometry.notchHeight
        let totalWidth = geometry.notchWidth + 2 * (wing + 14)
        let frame = CGRect(x: geometry.notchRect.midX - totalWidth / 2, y: geometry.screenFrame.maxY - height,
                           width: totalWidth, height: height)
        host.rootView = CollapsedNotchView(store: self.store, notchWidth: geometry.notchWidth, wingWidth: wing, height: height)
        panel.setFrame(frame, display: true)
        host.frame = CGRect(origin: .zero, size: frame.size)
        self.catcher?.frame = host.frame
        self.catcher?.setAccessibilityLabel(self.collapsedAccessibilityLabel)
        self.wingWidth = wing
    }

    private var collapsedAccessibilityLabel: String {
        guard let favorite = self.store.favoriteProvider else { return "AI usage. No providers connected." }
        if let meter = self.store.reading(for: favorite)?.summaryMeter {
            return "\(favorite.displayName): \(ValueFormatter.compact(for: meter)). Click for details."
        }
        return "\(favorite.displayName): \(self.store.status(for: favorite).label)"
    }

    /// Both wings share the width of the wider text so the camera stays centered. Kept tight so adjacent
    /// menu-bar items stay clickable.
    private func measureWing() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        var left = "AI usage"
        var right = "Connect"
        if let favorite = self.store.favoriteProvider {
            left = favorite.shortName + (self.store.isDemo ? " DEMO" : "")
            if let meter = self.store.reading(for: favorite)?.summaryMeter {
                right = ValueFormatter.compact(for: meter) + (self.store.status(for: favorite).isProblem ? "  ⚠" : "")
            } else {
                right = self.store.status(for: favorite).label
            }
        }
        return min(150, max(56, ceil(max(width(left), width(right))) + 4))
    }

    // MARK: Expanded

    func toggle() {
        self.isExpanded ? self.collapse() : self.expand()
    }

    func expand() {
        guard let geometry else { return }
        if self.expanded == nil {
            let panel = NotchPanel(contentRect: .zero)
            panel.allowsKey = true
            panel.onEscape = { [weak self] in self?.collapse() }
            let host = NSHostingView(rootView: NotchHostedPanel(
                store: self.store, router: self.router, actions: self.actions, topInset: geometry.notchHeight))
            panel.contentView = host
            self.expanded = panel
            self.expandedHost = host
        }
        self.expandedHost?.rootView = NotchHostedPanel(
            store: self.store, router: self.router, actions: self.actions, topInset: geometry.notchHeight)
        self.router.reset(for: self.store)
        self.isExpanded = true
        self.resizeExpanded(animated: false)
        self.collapsed?.orderOut(nil)
        self.expanded?.orderFrontRegardless()
        // Becoming key lets Escape and keyboard navigation work without activating Kazoo.
        self.expanded?.makeKey()
        self.installOutsideClickMonitor()
        self.store.refreshAll(manual: false)
    }

    func collapse() {
        guard self.isExpanded else { return }
        self.isExpanded = false
        self.expanded?.orderOut(nil)
        self.removeOutsideClickMonitor()
        if self.geometry != nil { self.collapsed?.orderFrontRegardless() }
    }

    private func resizeExpanded(animated: Bool) {
        guard self.isExpanded, let geometry, let panel = self.expanded, let host = self.expandedHost else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let width = max(size.width, geometry.notchWidth + 2 * (self.wingWidth + 14) + 28)
        let frame = CGRect(x: geometry.notchRect.midX - width / 2, y: geometry.screenFrame.maxY - size.height,
                           width: width, height: size.height)
        guard frame != panel.frame else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated, !reduceMotion, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func installOutsideClickMonitor() {
        self.removeOutsideClickMonitor()
        // Escape fallback: SwiftUI controls can swallow cancelOperation before it reaches the panel.
        self.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.isExpanded, event.window === self.expanded else { return event }
            self.collapse()
            return nil
        }
        self.outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor in self?.collapse() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = self.outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        self.outsideClickMonitor = nil
        if let monitor = self.escapeMonitor { NSEvent.removeMonitor(monitor) }
        self.escapeMonitor = nil
    }
}
