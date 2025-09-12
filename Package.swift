// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XCBuy",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "XCBuy",
            targets: ["XCBuy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/bizz84/SwiftyStoreKit.git", .upToNextMajor(from: "0.16.4"))
    ],
    targets: [
        .target(
            name: "XCBuy",
            dependencies: [
                "SwiftyStoreKit"
            ]
        ),
    ]
)
