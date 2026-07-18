// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "JellyfinCore",
    platforms: [
        .tvOS(.v26),
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "JellyfinCore",
            targets: ["JellyfinCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.0"),
    ],
    targets: [
        .target(
            name: "JellyfinCore",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
            ]
        ),
        .testTarget(
            name: "JellyfinCoreTests",
            dependencies: ["JellyfinCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
