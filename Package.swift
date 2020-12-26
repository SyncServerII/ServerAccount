// swift-tools-version:5.3
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
        //.package(url: "https://github.com/SyncServerII/ServerShared.git", .branch("master")),
        .package(url: "https://github.com/SyncServerII/ServerShared.git", from: "0.0.1"),
        .package(url: "https://github.com/IBM-Swift/Kitura-Credentials.git", from: "2.5.0"),
        .package(url: "https://github.com/IBM-Swift/Kitura.git", from: "2.9.1"),
        .package(url: "https://github.com/IBM-Swift/HeliumLogger.git", from: "1.8.1"),
    ],
    targets: [
        .target(
            name: "ServerAccount",
            dependencies: [
                "ServerShared",
                // For new condition feature, see https://forums.swift.org/t/package-manager-conditional-target-dependencies/31306/26
                .product(name: "Kitura", package: "Kitura", condition: .when(platforms: [.linux, .macOS])),
                .product(name: "HeliumLogger", package: "HeliumLogger", condition: .when(platforms: [.linux, .macOS])),
                .product(name: "Credentials", package: "Kitura-Credentials", condition: .when(platforms: [.linux, .macOS])),
            ],
            swiftSettings: [
                // So I can do basic development and editing with this on Mac OS. Otherwise if some dependent library uses this it will not get Account related code. See Account.swift.
                .define("SERVER", .when(platforms: [.macOS], configuration: .debug)),
            ]),
        .testTarget(
            name: "ServerAccountTests",
            dependencies: ["ServerAccount"]),
    ]
)
