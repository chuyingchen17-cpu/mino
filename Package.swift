// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MinoPoC",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MinoPoC", targets: ["MinoPoC"])
    ],
    targets: [
        .executableTarget(
            name: "MinoPoC",
            path: "Sources/MinoPoC"
        ),
        .testTarget(
            name: "MinoPoCTests",
            dependencies: ["MinoPoC"],
            path: "Tests/MinoPoCTests"
        )
    ]
)

