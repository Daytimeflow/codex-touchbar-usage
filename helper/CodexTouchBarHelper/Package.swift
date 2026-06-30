// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexTouchBarHelper",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "CodexTouchBarCore", targets: ["CodexTouchBarCore"]),
        .executable(name: "CodexTouchBarHelper", targets: ["CodexTouchBarHelper"])
    ],
    targets: [
        .target(name: "CodexTouchBarCore"),
        .executableTarget(
            name: "CodexTouchBarHelper",
            dependencies: ["CodexTouchBarCore"]
        ),
        .testTarget(
            name: "CodexTouchBarCoreTests",
            dependencies: ["CodexTouchBarCore"]
        )
    ]
)
