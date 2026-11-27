import AppKit
import KazooKit
import SwiftUI

/// Reference screenshots: real Kazoo views placed in a macOS menu-bar scene, plus the native windows.
/// Usage: swift run kazoo-render <dir> --screenshots
let menuBarHeight: CGFloat = 32
let notchWidth: CGFloat = 185

struct MenuBarStrip: View {
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
            Text("Finder").font(.system(size: 13, weight: .bold))
            ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            Image(systemName: "magnifyingglass")
            Text("Thu 9:41")
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 22)
        .frame(height: menuBarHeight)
        .background(Color(white: 0.94).opacity(0.92))
    }
}

struct DesktopScene<Panel: View>: View {
    let store: UsageStore
    let panel: Panel?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.84, green: 0.80, blue: 0.79), Color(red: 0.71, green: 0.67, blue: 0.67)],
                           startPoint: .top, endPoint: .bottom)
            MenuBarStrip()
            // Camera housing.
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                .fill(Color.black)
                .frame(width: notchWidth, height: menuBarHeight)
                .overlay(Circle().fill(Color(white: 0.12)).frame(width: 9, height: 9))
            if let panel {
                panel
            } else {
                CollapsedNotchView(store: self.store, notchWidth: notchWidth, wingWidth: wing(self.store), height: menuBarHeight)
            }
        }
        .frame(width: self.width, height: self.height)
        .clipped()
    }
}

@MainActor
func wing(_ store: UsageStore) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    func w(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
    guard let fav = store.favoriteProvider else { return 70 }
    let right = store.reading(for: fav)?.summaryMeter.map { ValueFormatter.compact(for: $0) } ?? ""
    return min(150, max(56, ceil(max(w(fav.shortName), w(right))) + 4))
}

/// Captures an AppKit-hosted SwiftUI window (List/Form need real AppKit views), including its title bar.
@MainActor
func captureWindow(_ view: some View, size: CGSize, title: String, to url: URL) {
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    window.title = title
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = NSHostingView(rootView: view)
    window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
    window.orderFrontRegardless()
    for _ in 0..<12 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    guard let frameView = window.contentView?.superview else { return }
    frameView.layoutSubtreeIfNeeded()
    guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
    frameView.cacheDisplay(in: frameView.bounds, to: rep)
    window.orderOut(nil)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
        print("wrote \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}

@MainActor
func renderScene(_ view: some View, to url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage else { print("failed: \(url.lastPathComponent)"); return }
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    print("wrote \(url.lastPathComponent) \(image.width)x\(image.height)")
}

@MainActor
func renderScreenshots(to out: URL) {
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let all = ProviderID.allCases
    let many = PreviewSupport.store(providers: all, favorite: .codex, pinned: [.codex, .claude, .openai])
    let noPanel: EmptyView? = nil

    renderScene(DesktopScene(store: many, panel: noPanel, width: 1100, height: 120),
                to: out.appendingPathComponent("notch-collapsed.png"))
    let claudeFav = PreviewSupport.store(providers: all, favorite: .claude)
    renderScene(DesktopScene(store: claudeFav, panel: noPanel, width: 1100, height: 120),
                to: out.appendingPathComponent("notch-collapsed-claude.png"))
    let openaiFav = PreviewSupport.store(providers: all, favorite: .openai)
    renderScene(DesktopScene(store: openaiFav, panel: noPanel, width: 1100, height: 120),
                to: out.appendingPathComponent("notch-collapsed-openai.png"))

    renderScene(DesktopScene(store: many, panel: PreviewSupport.panel(store: many, route: .overview),
                             width: 1100, height: 610),
                to: out.appendingPathComponent("notch-overview.png"))
    renderScene(DesktopScene(store: many, panel: PreviewSupport.panel(store: many, route: .detail(.claude), back: .overview),
                             width: 1100, height: 640),
                to: out.appendingPathComponent("notch-detail-claude.png"))
    renderScene(DesktopScene(store: many, panel: PreviewSupport.panel(store: many, route: .allProviders, back: .overview),
                             width: 1100, height: 650),
                to: out.appendingPathComponent("notch-all-providers.png"))
    let single = PreviewSupport.store(providers: [.copilot])
    renderScene(DesktopScene(store: single, panel: PreviewSupport.panel(store: single, route: .detail(.copilot)),
                             width: 1100, height: 480),
                to: out.appendingPathComponent("notch-copilot.png"))

    let connections = PreviewSupport.store(providers: [.claude, .codex, .copilot, .antigravity])
    captureWindow(ConnectionsView(store: connections, selection: .constant(.claude), solidSidebar: true),
                  size: CGSize(width: 900, height: 620), title: "Connections — Kazoo",
                  to: out.appendingPathComponent("connections.png"))
    captureWindow(ConnectionsView(store: connections, selection: .constant(.openai), solidSidebar: true),
                  size: CGSize(width: 900, height: 620), title: "Connections — Kazoo",
                  to: out.appendingPathComponent("connections-openai.png"))
    let updates = UpdateController(currentVersion: "0.1.2", buildNumber: "3",
                                   installMethod: .homebrew(brewPath: "/opt/homebrew/bin/brew"),
                                   fetcher: nil, defaults: UserDefaults(suiteName: "kazoo.render") ?? .standard)
    captureWindow(SettingsView(store: connections, updates: updates, openConnections: {}),
                  size: CGSize(width: 540, height: 760), title: "Kazoo Settings",
                  to: out.appendingPathComponent("settings.png"))
    captureWindow(SettingsView(store: connections, updates: updates, navigation: SettingsNavigation(tab: .updates),
                               openConnections: {}),
                  size: CGSize(width: 540, height: 520), title: "Kazoo Settings",
                  to: out.appendingPathComponent("settings-updates.png"))
}
