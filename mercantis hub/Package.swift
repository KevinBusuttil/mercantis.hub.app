// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "mercantis-hub",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(
            url: "https://github.com/KevinBusuttil/mercantis.core.app.git",
            branch: "main"
        )
    ],
    targets: [
        .executableTarget(
            name: "MercantisHub",
            dependencies: [
                .product(name: "MercantisCore", package: "mercantis.core.app")
            ]
        ),
        .testTarget(
            name: "MercantisHubTests",
            dependencies: ["MercantisHub"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
