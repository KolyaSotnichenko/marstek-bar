// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarstekKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarstekKit", targets: ["MarstekKit"]),
        .executable(name: "marstek-cli", targets: ["marstek-cli"]),
    ],
    targets: [
        .target(name: "MarstekKit"),
        .executableTarget(name: "marstek-cli", dependencies: ["MarstekKit"]),
        .testTarget(
            name: "MarstekKitTests",
            dependencies: ["MarstekKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
