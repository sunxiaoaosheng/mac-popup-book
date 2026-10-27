// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForestCabinPage", defaultLocalization: "en", platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ForestCabinWorker", targets: ["ForestCabinWorker"]),
        .library(name: "PaperCatBehavior", targets: ["PaperCatBehavior"]),
        .library(name: "PaperCatRendering", targets: ["PaperCatRendering"]),
        .library(name: "ForestCabinScene", targets: ["ForestCabinScene"]),
    ],
    dependencies: [.package(name: "MacPopupBook", path: "../..")],
    targets: [
        .target(
            name: "PaperCatBehavior",
            dependencies: [.product(name: "PopupBookCore", package: "MacPopupBook")],
            resources: [.process("Resources")]),
        .target(
            name: "PaperCatRendering",
            dependencies: [
                "PaperCatBehavior", .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
            ]),
        .target(
            name: "ForestCabinScene",
            dependencies: [
                .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
            ], resources: [.process("Resources")]),
        .executableTarget(
            name: "ForestCabinWorker",
            dependencies: [
                "PaperCatBehavior", "PaperCatRendering", "ForestCabinScene",
                .product(name: "PageWorkerKit", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
                .product(name: "PopupBookCore", package: "MacPopupBook"),
            ]),
        .executableTarget(
            name: "RenderCheck",
            dependencies: [
                "PaperCatBehavior", "PaperCatRendering", "ForestCabinScene",
                .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
                .product(name: "PopupBookRuntime", package: "MacPopupBook"),
                .product(name: "MacPlatform", package: "MacPopupBook"),
            ], path: "Tools/RenderCheck"),
        .executableTarget(
            name: "WindowCheck",
            dependencies: [
                "PaperCatBehavior", "PaperCatRendering", "ForestCabinScene",
                .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
                .product(name: "PopupBookRuntime", package: "MacPopupBook"),
                .product(name: "MacPlatform", package: "MacPopupBook"),
            ], path: "Tools/WindowCheck"),
        .executableTarget(
            name: "CompanionCheck",
            dependencies: [
                "PaperCatBehavior", "PaperCatRendering", "ForestCabinScene",
                .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
                .product(name: "PopupBookRuntime", package: "MacPopupBook"),
                .product(name: "MacPlatform", package: "MacPopupBook"),
            ], path: "Tools/CompanionCheck"),
        .executableTarget(
            name: "ExportAudio",
            dependencies: [
                "PaperCatBehavior", "PaperCatRendering", "ForestCabinScene",
                .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
                .product(name: "PopupBookRuntime", package: "MacPopupBook"),
                .product(name: "MacPlatform", package: "MacPopupBook"),
            ], path: "Tools/ExportAudio"),
        .testTarget(
            name: "CharacterTests",
            dependencies: ["PaperCatBehavior", .product(name: "PopupBookCore", package: "MacPopupBook")]),
        .testTarget(
            name: "ForestRenderingTests",
            dependencies: [
                "PaperCatBehavior", "PaperCatRendering", "ForestCabinScene",
                .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "SceneKitRendering", package: "MacPopupBook"),
            ], path: "Tests/RenderingTests"),
    ], swiftLanguageVersions: [.v5])
