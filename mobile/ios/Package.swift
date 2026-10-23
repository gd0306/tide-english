// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TideEnglishCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "TideEnglishCore", targets: ["TideEnglishCore"])],
    targets: [
        .target(name: "TideEnglishCore", path: "Domain"),
        .testTarget(name: "TideEnglishCoreTests", dependencies: ["TideEnglishCore"], path: "Tests")
    ]
)
