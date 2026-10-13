// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lumo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LumoCore"),
        .executableTarget(name: "Lumo", dependencies: ["LumoCore"]),
        .testTarget(name: "LumoCoreTests", dependencies: ["LumoCore"]),
    ]
)
