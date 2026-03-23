// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypeNest",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TypeNestCore",
            targets: ["TypeNestCore"]
        ),
    ],
    targets: [
        .target(
            name: "TypeNestCore"
        ),
        .testTarget(
            name: "TypeNestCoreTests",
            dependencies: ["TypeNestCore"]
        ),
    ]
)
