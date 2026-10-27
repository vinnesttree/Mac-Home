// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MacHome",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "MacHome", path: "Sources/MacHome")
    ]
)
