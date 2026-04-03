// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Signal",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "Signal",
            targets: ["Signal"]
        ),
    ],
    targets: [
        .target(
            name: "Signal",
            path: "Sources/Signal"
        ),
        .testTarget(
            name: "SignalTests",
            dependencies: ["Signal"],
            path: "Tests/SignalTests"
        ),
    ]
)
