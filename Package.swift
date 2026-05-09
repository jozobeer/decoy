// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Decoy",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Recorder", targets: ["Recorder"]),
        .library(name: "Broadcaster", targets: ["Broadcaster"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Recorder", dependencies: ["Domain"]),
        .target(name: "Broadcaster", dependencies: ["Domain"]),
        .testTarget(name: "RecorderTests", dependencies: ["Recorder", "Domain"]),
        .testTarget(name: "BroadcasterTests", dependencies: ["Broadcaster", "Domain"]),
    ]
)
