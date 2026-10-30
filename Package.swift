// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GPUUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GPUUsage", path: "Sources/GPUUsage")
    ]
)
