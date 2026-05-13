// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Decoy",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Decoy", targets: ["Decoy"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Recorder", targets: ["Recorder"]),
        .library(name: "Broadcaster", targets: ["Broadcaster"]),
        .library(name: "InMemoryClipStore", targets: ["InMemoryClipStore"]),
        .library(name: "InMemoryVirtualCameraSink", targets: ["InMemoryVirtualCameraSink"]),
        .library(name: "InMemoryCameraSource", targets: ["InMemoryCameraSource"]),
        .library(name: "FileSystemClipStore", targets: ["FileSystemClipStore"]),
        .library(name: "AVCameraSource", targets: ["AVCameraSource"]),
        .library(name: "AVCameraPermission", targets: ["AVCameraPermission"]),
        .library(name: "DependencyInjection", targets: ["DependencyInjection"]),
        .library(name: "AppCommandDispatcher", targets: ["AppCommandDispatcher"]),
        .library(name: "HotkeyService", targets: ["HotkeyService"]),
        .library(name: "MenuBarUI", targets: ["MenuBarUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.0.0"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "Decoy",
            dependencies: [
                "Domain",
                "Recorder",
                "Broadcaster",
                "AppCommandDispatcher",
                "AVCameraPermission",
                "DependencyInjection",
                "HotkeyService",
                "MenuBarUI",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            // `__TEXT,__info_plist` セクションに Info.plist を直接埋め込む。
            // SPM の `executableTarget` は `.app` バンドルを生成しないので
            // `resources: [.copy("Info.plist")]` だと `swift run` でも生成物の
            // バイナリ単体でも Info.plist が読まれない。`-sectcreate` で
            // バイナリの `__info_plist` セクションに直接埋めれば
            // `[NSBundle mainBundle].infoDictionary` 経由で OS から見える ―
            // `NSCameraUsageDescription` を OS の認可ダイアログが読みに来る経路。
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Decoy/Info.plist",
                ]),
            ]
        ),
        .target(
            name: "MenuBarUI",
            dependencies: [
                "Domain",
                "Recorder",
                "Broadcaster",
                "AppCommandDispatcher",
            ]
        ),
        .target(name: "Domain"),
        .target(
            name: "Recorder",
            dependencies: [
                "Domain",
                "DependencyInjection",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "Broadcaster",
            dependencies: [
                "Domain",
                "DependencyInjection",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(name: "InMemoryClipStore", dependencies: ["Domain"]),
        .target(name: "InMemoryVirtualCameraSink", dependencies: ["Domain"]),
        .target(name: "InMemoryCameraSource", dependencies: ["Domain"]),
        .target(name: "FileSystemClipStore", dependencies: ["Domain"]),
        .target(name: "AVCameraSource", dependencies: ["Domain"]),
        .target(name: "AVCameraPermission", dependencies: ["Domain"]),
        .target(
            name: "HotkeyService",
            dependencies: [
                "Domain",
                .product(name: "HotKey", package: "HotKey"),
            ]
        ),
        .target(
            name: "DependencyInjection",
            dependencies: [
                "Domain",
                "InMemoryClipStore",
                "InMemoryVirtualCameraSink",
                "InMemoryCameraSource",
                "AVCameraSource",
                "AVCameraPermission",
                "HotkeyService",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "AppCommandDispatcher",
            dependencies: [
                "Domain",
                "Recorder",
                "Broadcaster",
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
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ]
        ),
        .testTarget(
            name: "BroadcasterTests",
            dependencies: [
                "Broadcaster",
                "Domain",
                "DependencyInjection",
                "InMemoryCameraSource",
                "InMemoryClipStore",
                "InMemoryVirtualCameraSink",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ]
        ),
        .testTarget(
            name: "AppCommandDispatcherTests",
            dependencies: [
                "AppCommandDispatcher",
                "Broadcaster",
                "Recorder",
                "Domain",
                "DependencyInjection",
                "InMemoryCameraSource",
                "InMemoryClipStore",
                "InMemoryVirtualCameraSink",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Clocks", package: "swift-clocks"),
            ]
        ),
        .testTarget(name: "InMemoryClipStoreTests", dependencies: ["InMemoryClipStore", "Domain"]),
        .testTarget(name: "InMemoryVirtualCameraSinkTests", dependencies: ["InMemoryVirtualCameraSink", "Domain"]),
        .testTarget(name: "InMemoryCameraSourceTests", dependencies: ["InMemoryCameraSource", "Domain"]),
        .testTarget(name: "FileSystemClipStoreTests", dependencies: ["FileSystemClipStore", "Domain"]),
        .testTarget(name: "AVCameraSourceTests", dependencies: ["AVCameraSource", "Domain"]),
        .testTarget(name: "AVCameraPermissionTests", dependencies: ["AVCameraPermission", "Domain"]),
        .testTarget(name: "HotkeyServiceTests", dependencies: ["HotkeyService", "Domain"]),
        .testTarget(
            name: "MenuBarUITests",
            dependencies: [
                "MenuBarUI",
                "Domain",
                "Recorder",
                "Broadcaster",
                "AppCommandDispatcher",
                "DependencyInjection",
                "InMemoryCameraSource",
                "InMemoryClipStore",
                "InMemoryVirtualCameraSink",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ]
        ),
    ]
)
