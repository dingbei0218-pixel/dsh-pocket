// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DSHKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "DSHKit", targets: ["DSHKit"]),
        .executable(name: "dsh", targets: ["dsh"]),
    ],
    targets: [
        .target(
            name: "DSHKit",
            path: "Sources/DSHKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "dsh",
            dependencies: ["DSHKit"],
            path: "Sources/dsh",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DSHKitTests",
            dependencies: ["DSHKit"],
            path: "Tests/DSHKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
