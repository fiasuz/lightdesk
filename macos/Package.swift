// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiteDesk",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LiteDesk",
            path: "LiteDesk"
        ),
        .testTarget(
            name: "LiteDeskTests",
            dependencies: ["LiteDesk"],
            path: "Tests/LiteDeskTests"
        )
    ]
)
