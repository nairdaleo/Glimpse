// swift-tools-version: 5.9
import Foundation
import PackageDescription

// GLIMPSE_APP_STORE=1 builds the Mac App Store edition, which must not link
// Sparkle. The package dependency stays listed so Package.resolved is the same
// for both editions.
let appStore = ProcessInfo.processInfo.environment["GLIMPSE_APP_STORE"] == "1"

let package = Package(
    name: "Glimpse",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "GlimpseCore", targets: ["GlimpseCore"]),
        .library(name: "GlimpseMonitor", targets: ["GlimpseMonitor"]),
        .executable(name: "Glimpse", targets: ["GlimpseApp"]),
        .executable(name: "GlimpseLoginHelper", targets: ["GlimpseLoginHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "GlimpseCore"),
        .target(name: "GlimpseMonitor", dependencies: ["GlimpseCore"]),
        .executableTarget(name: "GlimpseApp", dependencies: ["GlimpseCore", "GlimpseMonitor"] + (appStore ? [] : [.product(name: "Sparkle", package: "Sparkle")]), resources: [.process("Resources")], swiftSettings: appStore ? [.define("APP_STORE")] : [], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "GlimpseLoginHelper"),
        .testTarget(name: "GlimpseCoreTests", dependencies: ["GlimpseCore"]),
        .testTarget(name: "GlimpseMonitorTests", dependencies: ["GlimpseMonitor", "GlimpseCore"]),
        .testTarget(name: "GlimpseAppTests", dependencies: ["GlimpseApp", "GlimpseCore"])
    ]
)
