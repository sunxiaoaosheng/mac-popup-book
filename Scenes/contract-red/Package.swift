// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StandalonePage", platforms: [.macOS(.v14)],
    products: [.executable(name: "StandaloneWorker", targets: ["PageWorker"])],
    dependencies: [.package(name: "MacPopupBook", path: "../..")],
    targets: [
        .target(name: "PageBehavior"),
        .executableTarget(
            name: "PageWorker",
            dependencies: [
                "PageBehavior", .product(name: "PopupBookCore", package: "MacPopupBook"),
                .product(name: "PageWorkerKit", package: "MacPopupBook"),
            ]),
        .testTarget(name: "PageTests", dependencies: ["PageBehavior"]),
    ], swiftLanguageVersions: [.v5])
