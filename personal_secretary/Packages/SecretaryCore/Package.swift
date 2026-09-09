// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretaryCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SecretaryCore", targets: ["SecretaryCore"]),
        .executable(name: "SecretarySmoke", targets: ["SecretarySmoke"])
    ],
    targets: [
        .target(
            name: "SecretaryCore",
            path: "Sources/SecretaryCore"
        ),
        .executableTarget(
            name: "SecretarySmoke",
            dependencies: ["SecretaryCore"],
            path: "Sources/SecretarySmoke"
        ),
        .testTarget(
            name: "SecretaryCoreTests",
            dependencies: ["SecretaryCore"],
            path: "Tests/SecretaryCoreTests"
        )
    ]
)
