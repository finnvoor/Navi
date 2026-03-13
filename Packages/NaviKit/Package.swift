// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "NaviKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "NaviKit",
            targets: ["NaviKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/square/Valet", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "NaviKit",
            dependencies: [
                .product(name: "Valet", package: "Valet"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
