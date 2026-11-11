// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ent303Rise",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ent303Rise",
            path: "Sources/Ent303Rise"
        )
    ]
)
