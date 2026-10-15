// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiskLens",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DiskLens", path: "Sources/DiskLens"),
        .testTarget(name: "DiskLensTests", dependencies: ["DiskLens"], path: "Tests/DiskLensTests"),
    ]
)
