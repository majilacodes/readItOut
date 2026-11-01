// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ReadItOut",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ReadItOut",
            path: "Sources/ReadItOut"
        )
    ],
    swiftLanguageModes: [.v5]
)
