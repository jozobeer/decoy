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
        .library(name: "InMemoryClipStore", targets: ["InMemoryClipStore"]),
        .library(name: "InMemoryVirtualCameraSink", targets: ["InMemoryVirtualCameraSink"]),
        .library(name: "InMemoryCameraSource", targets: ["InMemoryCameraSource"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Recorder", dependencies: ["Domain"]),
        .target(name: "Broadcaster", dependencies: ["Domain"]),
        .target(name: "InMemoryClipStore", dependencies: ["Domain"]),
        .target(name: "InMemoryVirtualCameraSink", dependencies: ["Domain"]),
        .target(name: "InMemoryCameraSource", dependencies: ["Domain"]),
        .testTarget(name: "RecorderTests", dependencies: ["Recorder", "Domain"]),
        .testTarget(name: "BroadcasterTests", dependencies: ["Broadcaster", "Domain"]),
        .testTarget(name: "InMemoryClipStoreTests", dependencies: ["InMemoryClipStore", "Domain"]),
        .testTarget(name: "InMemoryVirtualCameraSinkTests", dependencies: ["InMemoryVirtualCameraSink", "Domain"]),
        .testTarget(name: "InMemoryCameraSourceTests", dependencies: ["InMemoryCameraSource", "Domain"]),
    ]
)
