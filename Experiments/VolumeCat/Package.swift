// swift-tools-version: 5.9
import PackageDescription

let shared: Target.Dependency = .product(name: "PopupBookCore", package: "MacPopupBook")
let rendering: Target.Dependency = .product(name: "SceneKitRendering", package: "MacPopupBook")
let cat: Target.Dependency = .product(name: "PaperCatBehavior", package: "ForestCabinPage")
let catRendering: Target.Dependency = .product(name: "PaperCatRendering", package: "ForestCabinPage")
let forest: Target.Dependency = .product(name: "ForestCabinScene", package: "ForestCabinPage")
let package = Package(
    name: "VolumeCatExperiments", platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "MacPopupBook", path: "../.."),
        .package(name: "ForestCabinPage", path: "../../Scenes/forest-cabin"),
    ],
    targets: [
        .target(name: "VolumeCatRendering", dependencies: [shared, rendering, cat]),
        .executableTarget(name: "AssetCheck", path: "Tools/AssetCheck"),
        .executableTarget(name: "RealityAssetCheck", path: "Tools/RealityAssetCheck"),
        .executableTarget(name: "PlaybackCheck", dependencies: [rendering], path: "Tools/PlaybackCheck"),
        .executableTarget(
            name: "OffscreenCheck",
            dependencies: [shared, rendering, cat, catRendering, forest, "VolumeCatRendering"],
            path: "Tools/OffscreenCheck"),
        .executableTarget(
            name: "CandidateSceneCheck",
            dependencies: [shared, rendering, cat, forest, "VolumeCatRendering"],
            path: "Tools/CandidateSceneCheck"),
        .testTarget(
            name: "VolumeTests", dependencies: [shared, rendering, "VolumeCatRendering"], path: "Tests"),
    ], swiftLanguageVersions: [.v5])
