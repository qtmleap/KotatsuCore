// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "KotatsuCore",
    platforms: [
        .tvOS(.v26),
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "KotatsuCore",
            targets: ["KotatsuCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", from: "2.0.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "KotatsuCore",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "SwiftyBeaver", package: "SwiftyBeaver"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ]
        ),
        .testTarget(
            name: "KotatsuCoreTests",
            dependencies: ["KotatsuCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
