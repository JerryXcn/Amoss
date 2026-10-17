// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Amoss",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AmossCore", targets: ["AmossCore"]),
        .executable(name: "Amoss", targets: ["Amoss"])
    ],
    targets: [
        .target(name: "AmossCore", resources: [.process("Resources")]),
        .executableTarget(name: "Amoss", dependencies: ["AmossCore"]),
        .testTarget(name: "AmossCoreTests", dependencies: ["AmossCore"])
    ]
)
