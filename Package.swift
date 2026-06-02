// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "parlance-swift-sdk",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "ParlanceSDK",
            targets: ["ParlanceSDK"]
        ),
    ],
    targets: [
        .target(
            name: "ParlanceSDK",
            path: "Sources/ParlanceSDK"
        ),
        .testTarget(
            name: "ParlanceSDKTests",
            dependencies: ["ParlanceSDK"],
            path: "Tests/ParlanceSDKTests"
        ),
    ]
)
