// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MagicClip",
    // 개인용: 이 Mac의 macOS만 대상으로 한다.
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "MagicClipCore"),
        .executableTarget(name: "MagicClip", dependencies: ["MagicClipCore"]),
        .testTarget(
            name: "MagicClipCoreTests",
            dependencies: ["MagicClipCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
