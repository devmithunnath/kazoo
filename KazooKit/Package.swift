// swift-tools-version: 6.0
import PackageDescription

// CodexBar is pinned by revision (tag v0.85.0). Revision pinning is required because CodexBar itself
// pins Vortex by revision and uses platform-conditional unsafe linker flags.
let codexBarRevision = "5dd48cab770a326691b25a124d37ffee12c5f7ac"

let package = Package(
    name: "KazooKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KazooKit", targets: ["KazooKit"]),
        .executable(name: "kazoo-probe", targets: ["KazooProbe"]),
        .executable(name: "kazoo-render", targets: ["KazooRender"]),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/CodexBar.git", revision: codexBarRevision),
    ],
    targets: [
        .target(
            name: "KazooKit",
            dependencies: [
                .product(name: "CodexBarCore", package: "CodexBar"),
            ],
            resources: [
                .copy("Resources/ThirdPartyNotices.txt"),
            ]),
        // Developer probe: fetch one live provider and print the normalized reading (no secrets).
        .executableTarget(
            name: "KazooProbe",
            dependencies: ["KazooKit"]),
        // Renders fixture-backed panel states to PNG for visual QA (no screen-recording permission needed).
        .executableTarget(
            name: "KazooRender",
            dependencies: ["KazooKit"]),
        .testTarget(
            name: "KazooKitTests",
            dependencies: [
                "KazooKit",
                .product(name: "CodexBarCore", package: "CodexBar"),
            ]),
    ])
