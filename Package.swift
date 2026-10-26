// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPopupBook",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ForestBook", targets: ["ForestCabinApp"])],
    targets: [
        .target(name: "PopupBookCore", path: "Modules/PopupBookCore"),
        .target(name: "PopupBookRuntime", dependencies: ["PopupBookCore"], path: "Modules/PopupBookRuntime"),
        .target(name: "MacPlatform", dependencies: ["PopupBookCore"], path: "Modules/MacPlatform"),
        .target(
            name: "SceneKitRendering", dependencies: ["PopupBookCore"], path: "Modules/SceneKitRendering"),
        .target(
            name: "PaperCatBehavior", dependencies: ["PopupBookCore"], path: "Characters/PaperCat/Behavior"),
        .target(
            name: "PaperCatRendering",
            dependencies: ["PopupBookCore", "SceneKitRendering", "PaperCatBehavior"],
            path: "Characters/PaperCat/Rendering"),
        .target(
            name: "ForestCabinScene", dependencies: ["PopupBookCore", "SceneKitRendering"],
            path: "Apps/ForestCabin/Scene"),
        .executableTarget(
            name: "ForestCabinApp",
            dependencies: [
                "PopupBookCore", "PopupBookRuntime", "MacPlatform", "SceneKitRendering", "PaperCatBehavior",
                "PaperCatRendering", "ForestCabinScene",
            ], path: "Apps/ForestCabin/App"),
        .executableTarget(
            name: "RenderCheck",
            dependencies: [
                "PopupBookCore", "SceneKitRendering", "PaperCatBehavior", "PaperCatRendering",
                "ForestCabinScene",
            ], path: "Tools/RenderCheck"),
        .executableTarget(
            name: "WindowCheck",
            dependencies: [
                "PopupBookCore", "PopupBookRuntime", "MacPlatform", "SceneKitRendering", "PaperCatBehavior",
                "PaperCatRendering", "ForestCabinScene",
            ], path: "Tools/WindowCheck"),
        .executableTarget(name: "ExportAudio", dependencies: ["PopupBookCore"], path: "Tools/ExportAudio"),
        .testTarget(name: "MacPlatformTests", dependencies: ["MacPlatform"], path: "Tests/MacPlatformTests"),
        .testTarget(name: "CoreTests", dependencies: ["PopupBookCore"], path: "Tests/CoreTests"),
        .testTarget(
            name: "RuntimeTests", dependencies: ["PopupBookCore", "PopupBookRuntime"],
            path: "Tests/RuntimeTests"),
        .testTarget(
            name: "CharacterTests", dependencies: ["PopupBookCore", "PaperCatBehavior"],
            path: "Tests/CharacterTests"),
        .testTarget(
            name: "RenderingTests",
            dependencies: [
                "PopupBookCore", "SceneKitRendering", "PaperCatBehavior", "PaperCatRendering",
                "ForestCabinScene",
            ], path: "Tests/RenderingTests"),
    ],
    swiftLanguageVersions: [.v5]
)
