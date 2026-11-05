// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BaselineCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BaselineCore", targets: ["BaselineCore"])
    ],
    targets: [
        .target(name: "BaselineCore"),
        .testTarget(
            name: "BaselineCoreTests",
            dependencies: ["BaselineCore"]
        )
    ]
)
