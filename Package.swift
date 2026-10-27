// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPopupBook", defaultLocalization: "en", platforms: [.macOS(.v14)],
    products: [
        .library(name: "PopupBookCore", targets: ["PopupBookCore"]),
        .library(name: "PopupBookRuntime", targets: ["PopupBookRuntime"]),
        .library(name: "MacPlatform", targets: ["MacPlatform"]),
        .library(name: "SceneKitRendering", targets: ["SceneKitRendering"]),
        .library(name: "PageWorkerKit", targets: ["PageWorkerKit"]),
        .executable(name: "ForestBook", targets: ["BookHostApp"]),
        .executable(name: "BookIntegrationCheck", targets: ["BookIntegrationCheck"]),
    ],
    targets: [
        .target(name: "PopupBookCore", path: "Modules/PopupBookCore", resources: [.process("Resources")]),
        .target(
            name: "PopupBookRuntime", dependencies: ["PopupBookCore"], path: "Modules/PopupBookRuntime",
            resources: [.process("Resources")]),
        .target(name: "PageTransport", dependencies: ["PopupBookCore"], path: "Modules/PageTransport"),
        .target(
            name: "MacPlatform", dependencies: ["PopupBookCore", "PageTransport"],
            path: "Modules/MacPlatform", resources: [.process("Resources")]),
        .target(
            name: "SceneKitRendering", dependencies: ["PopupBookCore"], path: "Modules/SceneKitRendering",
            resources: [.process("Resources")]),
        .target(
            name: "PageWorkerKit", dependencies: ["PopupBookCore", "PageTransport"],
            path: "Modules/PageWorkerKit"),
        .executableTarget(
            name: "BookHostApp",
            dependencies: ["PopupBookCore", "PopupBookRuntime", "MacPlatform", "PageTransport"],
            path: "Apps/BookHost", resources: [.process("Resources")]),
        .executableTarget(
            name: "BookIntegrationCheck", dependencies: ["PopupBookCore", "PopupBookRuntime", "MacPlatform"],
            path: "Tools/BookIntegrationCheck"),
        .testTarget(name: "CoreTests", dependencies: ["PopupBookCore"], path: "Tests/CoreTests"),
        .testTarget(
            name: "RuntimeTests", dependencies: ["PopupBookCore", "PopupBookRuntime"],
            path: "Tests/RuntimeTests"),
        .testTarget(name: "MacPlatformTests", dependencies: ["MacPlatform"], path: "Tests/MacPlatformTests"),
        .testTarget(
            name: "RenderingTests", dependencies: ["PopupBookCore", "SceneKitRendering"],
            path: "Tests/RenderingTests"),
    ], swiftLanguageVersions: [.v5])
