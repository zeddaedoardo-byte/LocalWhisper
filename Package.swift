// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LocalWhisperFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalWhisperFlow", targets: ["LocalWhisperFlow"])
    ],
    targets: [
        .executableTarget(name: "LocalWhisperFlow"),
        .testTarget(
            name: "LocalWhisperFlowTests",
            dependencies: ["LocalWhisperFlow"]
        )
    ]
)
