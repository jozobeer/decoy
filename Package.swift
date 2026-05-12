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
        .library(name: "DependencyInjection", targets: ["DependencyInjection"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
    ],
    targets: [
        .target(name: "Domain"),
        .target(
            name: "Recorder",
            dependencies: [
                "Domain",
                "DependencyInjection",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(name: "Broadcaster", dependencies: ["Domain"]),
        .target(name: "InMemoryClipStore", dependencies: ["Domain"]),
        .target(name: "InMemoryVirtualCameraSink", dependencies: ["Domain"]),
        .target(name: "InMemoryCameraSource", dependencies: ["Domain"]),
        .target(
            name: "DependencyInjection",
            dependencies: [
                "Domain",
                "InMemoryClipStore",
                "InMemoryVirtualCameraSink",
                "InMemoryCameraSource",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "RecorderTests",
            dependencies: [
                "Recorder",
                "Domain",
                "DependencyInjection",
                "InMemoryCameraSource",
                "InMemoryClipStore",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(name: "BroadcasterTests", dependencies: ["Broadcaster", "Domain"]),
        .testTarget(name: "InMemoryClipStoreTests", dependencies: ["InMemoryClipStore", "Domain"]),
        .testTarget(name: "InMemoryVirtualCameraSinkTests", dependencies: ["InMemoryVirtualCameraSink", "Domain"]),
        .testTarget(name: "InMemoryCameraSourceTests", dependencies: ["InMemoryCameraSource", "Domain"]),
    ]
)
