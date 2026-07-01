// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "materialTun",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "materialTun", targets: ["materialTun"]),
        .executable(name: "materialTunHelper", targets: ["materialTunHelper"])
    ],
    targets: [
        .executableTarget(
            name: "materialTun",
            path: "Sources/materialTun"
        ),
        .executableTarget(
            name: "materialTunHelper",
            path: "Sources/materialTunHelper"
        )
    ]
)
