// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Andromac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Andromac", path: "Sources/Andromac"),
        .executableTarget(name: "andromac-testclient", path: "Sources/andromac-testclient"),
    ]
)
