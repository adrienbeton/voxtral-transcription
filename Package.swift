// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Voxtral",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "VoxtralCore"),
        .executableTarget(name: "Voxtral", dependencies: ["VoxtralCore"]),
        .testTarget(name: "VoxtralCoreTests", dependencies: ["VoxtralCore"]),
    ]
)
