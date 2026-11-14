// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glimpse",
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
        .executableTarget(name: "GlimpseApp", dependencies: ["GlimpseCore", "GlimpseMonitor", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "GlimpseLoginHelper"),
        .testTarget(name: "GlimpseCoreTests", dependencies: ["GlimpseCore"]),
        .testTarget(name: "GlimpseMonitorTests", dependencies: ["GlimpseMonitor", "GlimpseCore"]),
        .testTarget(name: "GlimpseAppTests", dependencies: ["GlimpseApp", "GlimpseCore"])
    ]
)
