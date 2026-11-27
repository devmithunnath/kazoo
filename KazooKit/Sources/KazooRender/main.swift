import AppKit
import KazooKit
import SwiftUI

// Usage: swift run kazoo-render <output-dir>
@MainActor
func render(_ view: some View, to url: URL) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
    else { print("failed: \(url.lastPathComponent)"); return }
    try? png.write(to: url)
    print("wrote \(url.lastPathComponent) \(Int(image.size.width))x\(Int(image.size.height))")
}

@MainActor
func main() {
    let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "renders", isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let all = ProviderID.allCases
    let many = PreviewSupport.store(providers: all, pinned: [.codex, .claude, .openai])
    render(CollapsedNotchView(store: many, notchWidth: 185, wingWidth: 118, height: 32).background(Color.gray),
           to: out.appendingPathComponent("collapsed-codex.png"))
    let openaiFav = PreviewSupport.store(providers: [.openai, .codex], favorite: .openai)
    render(CollapsedNotchView(store: openaiFav, notchWidth: 185, wingWidth: 100, height: 32).background(Color.gray),
           to: out.appendingPathComponent("collapsed-openai.png"))
    render(PreviewSupport.panel(store: many, route: .overview), to: out.appendingPathComponent("overview.png"))
    render(PreviewSupport.panel(store: many, route: .allProviders, back: .overview),
           to: out.appendingPathComponent("all-providers.png"))
    for provider in all {
        render(PreviewSupport.panel(store: many, route: .detail(provider), back: .overview),
               to: out.appendingPathComponent("detail-\(provider.rawValue).png"))
    }
    let single = PreviewSupport.store(providers: [.copilot])
    render(PreviewSupport.panel(store: single, route: .detail(.copilot)), to: out.appendingPathComponent("single-copilot.png"))
    let stale = PreviewSupport.store(providers: [.codex, .claude], statuses: [.codex: .offline, .claude: .expired])
    render(PreviewSupport.panel(store: stale, route: .detail(.codex), back: .overview), to: out.appendingPathComponent("stale-codex.png"))
    render(PreviewSupport.panel(store: stale, route: .overview), to: out.appendingPathComponent("overview-stale.png"))
    let empty = PreviewSupport.store(providers: [])
    render(PreviewSupport.panel(store: empty, route: .empty), to: out.appendingPathComponent("empty.png"))
}

MainActor.assumeIsolated { main() }
