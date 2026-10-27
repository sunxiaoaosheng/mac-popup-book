// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IsolationProbe", platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ProbeHost", targets: ["ProbeHost"]),
        .executable(name: "ProbeWorker", targets: ["ProbeWorker"]),
    ],
    targets: [
        .target(name: "ProbeWire"),
        .executableTarget(name: "ProbeHost", dependencies: ["ProbeWire"]),
        .executableTarget(name: "ProbeWorker", dependencies: ["ProbeWire"]),
    ], swiftLanguageVersions: [.v5])
