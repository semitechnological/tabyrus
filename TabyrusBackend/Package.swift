// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TabyrusBackend",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TabyrusBackend", targets: ["TabyrusBackend"])
    ],
    dependencies: [],
    targets: [
        .systemLibrary(
            name: "eqswiftFFI",
            path: "Sources/eqswiftFFI"
        ),
        .target(
            name: "EqSwift",
            dependencies: ["eqswiftFFI"],
            path: "Sources/EqSwift"
        ),
        .target(
            name: "TabyrusBackend",
            dependencies: ["EqSwift"],
            exclude: ["lib.rs"]
        )
    ]
)
