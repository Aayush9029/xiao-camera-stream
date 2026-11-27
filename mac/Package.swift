// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XiaoCam",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "XiaoCamCore", targets: ["XiaoCamCore"]),
        .library(name: "XiaoCamKit", targets: ["XiaoCamKit"]),
        .executable(name: "XiaoCam", targets: ["XiaoCam"]),
        .executable(name: "xiaocam-cli", targets: ["XiaoCamCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.7.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.7.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "XiaoCamCore",
            dependencies: [
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            ]
        ),
        .target(
            name: "XiaoCamKit",
            dependencies: [
                "XiaoCamCore",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "Tagged", package: "swift-tagged"),
            ]
        ),
        .executableTarget(
            name: "XiaoCam",
            dependencies: ["XiaoCamKit"],
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "XiaoCamCLI",
            dependencies: [
                "XiaoCamKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "XiaoCamCoreTests",
            dependencies: [
                "XiaoCamCore",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "XiaoCamKitTests",
            dependencies: [
                "XiaoCamKit",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            ]
        ),
    ]
)
