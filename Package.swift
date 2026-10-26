// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ForestBook", platforms: [.macOS(.v14)], products: [.executable(name: "ForestBook", targets: ["ForestBook"])], targets: [.executableTarget(name: "ForestBook", path: "Sources", linkerSettings: [.linkedFramework("SceneKit"), .linkedFramework("IOKit"), .linkedFramework("AVFoundation")])])
