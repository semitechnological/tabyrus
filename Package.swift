// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tabyrus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "tabyrus", targets: ["Tabyrus"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Tabyrus",
            dependencies: [],
            path: "src",
            exclude: ["lib.rs"],
            linkerSettings: [
                .unsafeFlags(["-Ltarget/debug", "-ltabyrus_backend"])
            ]
        )
    ]
)
