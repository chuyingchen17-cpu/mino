// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Mino",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mino", targets: ["MinoApp"])
    ],
    targets: [
        .target(
            name: "MinoDomain",
            path: "Sources/MinoDomain"
        ),
        .target(
            name: "MinoRuntime",
            dependencies: ["MinoDomain"],
            path: "Sources/MinoRuntime"
        ),
        .target(
            name: "MinoPresentation",
            dependencies: ["MinoDomain"],
            path: "Sources/MinoPresentation",
            exclude: [
                "Resources/partner-avatar.png",
                "Resources/shared-room-away.png",
                "Resources/shared-room.png"
            ],
            resources: [
                .copy("Resources/PetFrames")
            ]
        ),
        .target(
            name: "MinoInfrastructure",
            dependencies: ["MinoDomain"],
            path: "Sources/MinoInfrastructure"
        ),
        .target(
            name: "MinoSecurity",
            dependencies: ["MinoDomain"],
            path: "Sources/MinoSecurity",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "MinoPersistence",
            dependencies: ["MinoDomain"],
            path: "Sources/MinoPersistence"
        ),
        .target(
            name: "MinoAgent",
            dependencies: ["MinoDomain"],
            path: "Sources/MinoAgent"
        ),
        .executableTarget(
            name: "MinoApp",
            dependencies: [
                "MinoDomain",
                "MinoRuntime",
                "MinoPresentation",
                "MinoInfrastructure",
                "MinoSecurity",
                "MinoPersistence",
                "MinoAgent"
            ],
            path: "Sources/MinoApp"
        ),
        .testTarget(
            name: "MinoDomainTests",
            dependencies: ["MinoDomain"],
            path: "Tests/MinoDomainTests"
        ),
        .testTarget(
            name: "MinoRuntimeTests",
            dependencies: ["MinoDomain", "MinoRuntime"],
            path: "Tests/MinoRuntimeTests"
        ),
        .testTarget(
            name: "MinoPresentationTests",
            dependencies: ["MinoDomain", "MinoPresentation"],
            path: "Tests/MinoPresentationTests"
        ),
        .testTarget(
            name: "MinoInfrastructureTests",
            dependencies: ["MinoDomain", "MinoInfrastructure"],
            path: "Tests/MinoInfrastructureTests"
        ),
        .testTarget(
            name: "MinoSecurityTests",
            dependencies: ["MinoDomain", "MinoSecurity"],
            path: "Tests/MinoSecurityTests"
        ),
        .testTarget(
            name: "MinoPersistenceTests",
            dependencies: ["MinoDomain", "MinoPersistence"],
            path: "Tests/MinoPersistenceTests"
        ),
        .testTarget(
            name: "MinoAgentTests",
            dependencies: ["MinoDomain", "MinoAgent"],
            path: "Tests/MinoAgentTests"
        ),
        .testTarget(
            name: "MinoAppTests",
            dependencies: ["MinoApp", "MinoDomain", "MinoInfrastructure"],
            path: "Tests/MinoAppTests"
        )
    ]
)
