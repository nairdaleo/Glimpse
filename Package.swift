// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glimpse",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "GlimpseCore", targets: ["GlimpseCore"]),
        .library(name: "GlimpseMonitor", targets: ["GlimpseMonitor"]),
        .executable(name: "Glimpse", targets: ["GlimpseApp"])
    ],
    targets: [
        .target(name: "GlimpseCore"),
        .target(name: "GlimpseMonitor", dependencies: ["GlimpseCore"]),
        .executableTarget(name: "GlimpseApp", dependencies: ["GlimpseCore", "GlimpseMonitor"]),
        .testTarget(name: "GlimpseCoreTests", dependencies: ["GlimpseCore"]),
        .testTarget(name: "GlimpseMonitorTests", dependencies: ["GlimpseMonitor", "GlimpseCore"])
    ]
)
