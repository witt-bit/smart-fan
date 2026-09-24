// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SmartFan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "smart-fan", targets: ["SmartFanCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SmartFanLocalization",
            resources: [.process("Resources")]
        ),
        .target(
            name: "SmartFanCore",
            path: "Sources/SmartFanCore",
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "SmartFanCLI",
            dependencies: [
                "SmartFanCore",
                "SmartFanLocalization",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SmartFanCLI"
        ),
        .executableTarget(
            name: "SmartFanApp",
            dependencies: ["SmartFanCore", "SmartFanLocalization"],
            path: "Sources/SmartFanApp"
        ),
        .testTarget(
            name: "SmartFanTests",
            dependencies: ["SmartFanCore", "SmartFanApp", "SmartFanLocalization"],
            path: "Tests/SmartFanTests"
        ),
    ]
)
