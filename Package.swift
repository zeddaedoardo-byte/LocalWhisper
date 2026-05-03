// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LocalWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalWhisper", targets: ["LocalWhisper"])
    ],
    targets: [
        .executableTarget(name: "LocalWhisper"),
        .testTarget(
            name: "LocalWhisperTests",
            dependencies: ["LocalWhisper"]
        )
    ]
)
