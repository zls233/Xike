// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Xike",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Xike", targets: ["Xike"])
    ],
    targets: [
        .executableTarget(
            name: "Xike",
            path: "Sources/Xike",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "XikeTests",
            dependencies: ["Xike"],
            path: "Tests/XikeTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
