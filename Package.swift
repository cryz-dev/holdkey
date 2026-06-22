// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoldKey",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "HoldKey",
            path: "Sources/HoldKey"
        )
    ]
)
