import AppKit
import Combine
import KazooKit
import SwiftUI

/// Menu-bar fallback for displays without a notch (or when the user always wants it).
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: UsageStore
    private let router: PanelRouter
    private let actions: PanelActions
    private let menuProvider: () -> NSMenu
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore, router: PanelRouter, actions: PanelActions, menuProvider: @escaping () -> NSMenu) {
        self.store = store
        self.router = router
        self.actions = actions
        self.menuProvider = menuProvider
        super.init()
        self.popover.behavior = .transient
        self.popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.popover.delegate = self
        let controller = NSHostingController(rootView: NotchPanelView(
            store: store, router: router, actions: actions, topInset: 18))
        controller.sizingOptions = [.preferredContentSize]
        self.popover.contentViewController = controller
        store.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &self.cancellables)
    }

    func setVisible(_ visible: Bool) {
        if visible, self.item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(self.clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            self.item = item
            self.updateTitle()
        } else if !visible, let item = self.item {
            self.popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    var isVisible: Bool { self.item != nil }

    func close() { self.popover.performClose(nil) }

    private func updateTitle() {
        guard let button = self.item?.button else { return }
        let image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        var title = ""
        var accessibility = self.store.preferences.displayName
        if let favorite = self.store.favoriteProvider {
            if let meter = self.store.reading(for: favorite)?.summaryMeter {
                let compact: String = switch meter.value {
                case .remainingPercent: "\(meter.gauge?.percent ?? 0)%"
                default: ValueFormatter.numeral(for: meter)
                }
                title = " \(favorite.shortName) \(compact)"
                accessibility = "\(favorite.displayName): \(ValueFormatter.compact(for: meter))"
            } else {
                title = " \(favorite.shortName)"
            }
            if self.store.isDemo { title += " (demo)" }
        }
        button.title = title
        button.setAccessibilityLabel(accessibility)
        button.toolTip = "\(self.store.preferences.displayName) — AI usage"
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            if let item = self.item {
                item.menu = self.menuProvider()
                item.button?.performClick(nil)
                item.menu = nil
            }
            return
        }
        if self.popover.isShown {
            self.popover.performClose(nil)
        } else {
            self.router.reset(for: self.store)
            self.popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            self.popover.contentViewController?.view.window?.makeKey()
            self.store.refreshAll(manual: false)
        }
    }
}
