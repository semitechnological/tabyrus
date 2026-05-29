// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TabyrusBackend",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TabyrusBackend", targets: ["TabyrusBackend"])
    ],
    dependencies: [
        .package(name: "EqSwift", path: "../../eqswift/swift")
    ],
    targets: [
        .target(
            name: "TabyrusBackend",
            dependencies: [.product(name: "EqSwift", package: "EqSwift")],
            exclude: ["lib.rs"]
        )
    ]
)
