// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OmniIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OmniIsland",
            path: "Sources/OmniIsland"
        )
    ]
)
