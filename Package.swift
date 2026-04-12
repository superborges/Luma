// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Luma",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Luma",
            targets: ["Luma"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Luma",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "LumaTests",
            dependencies: ["Luma"]
        ),
    ]
)
