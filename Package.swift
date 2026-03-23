// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VaporDBGuard",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "VaporDBGuard",
            targets: ["VaporDBGuard"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0")
    ],
    targets: [
        .target(
            name: "VaporDBGuard",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
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
