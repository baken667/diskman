// swift-tools-version: 6.0
import PackageDescription

// All disk logic lives here so the GUI, the CLI and the MCP server share one implementation.
let package = Package(
    name: "DiskmanCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DiskmanCore", targets: ["DiskmanCore"])],
    targets: [
        .target(name: "DiskmanCore"),
        .testTarget(name: "DiskmanCoreTests", dependencies: ["DiskmanCore"]),
    ]
)
