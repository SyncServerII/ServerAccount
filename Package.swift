// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ServerAccount",
    products: [
        .library(
            name: "ServerAccount",
            targets: ["ServerAccount"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SyncServerII/ServerShared.git", .branch("master")),
        .package(url: "https://github.com/IBM-Swift/Kitura-Credentials.git", from: "2.5.0"),
        .package(url: "https://github.com/IBM-Swift/Kitura.git", from: "2.9.1"),
        .package(url: "https://github.com/IBM-Swift/HeliumLogger.git", from: "1.8.1"),
    ],
    targets: [
        .target(
            name: "ServerAccount",
            dependencies: ["ServerShared", "Kitura", "HeliumLogger",
                .product(name: "Credentials", package: "Kitura-Credentials"),
            ]),
        .testTarget(
            name: "ServerAccountTests",
            dependencies: ["ServerAccount"]),
    ]
)