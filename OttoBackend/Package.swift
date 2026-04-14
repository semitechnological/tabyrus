// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OttoBackend",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "OttoBackend",
            targets: ["OttoBackend"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OttoBackend",
            dependencies: []
        ),
    ]
)