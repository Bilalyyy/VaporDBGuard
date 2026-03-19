// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VaporDBGuard",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "VaporDBGuard",
            targets: ["VaporDBGuard"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
    ],
    targets: [
        .target(
            name: "VaporDBGuard",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        .testTarget(
            name: "VaporDBGuardTests",
            dependencies: [
                .target(name: "VaporDBGuard"),
                .product(name: "VaporTesting", package: "vapor")
            ]
        ),
    ]
)
