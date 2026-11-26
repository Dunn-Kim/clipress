// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipress",
    // 개인용: 이 Mac의 macOS만 대상으로 한다.
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "ClipressCore"),
        .executableTarget(name: "Clipress", dependencies: ["ClipressCore"]),
        .testTarget(
            name: "ClipressCoreTests",
            dependencies: ["ClipressCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
