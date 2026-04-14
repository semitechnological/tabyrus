// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Otto",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "otto", targets: ["Otto"])
    ],
    dependencies: [
        .package(path: "./OttoBackend")
    ],
    targets: [
        .executableTarget(
            name: "Otto",
            dependencies: ["OttoBackend"],
            path: "src",
            resources: []
        )
    ]
)