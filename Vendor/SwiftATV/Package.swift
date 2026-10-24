// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-atv",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
    ],
    products: [
        .library(
            name: "SwiftATV",
            targets: ["SwiftATV"]
        )
    ],
    dependencies: [
        .package(path: "../swift-nio"),
        .package(path: "../swift-protobuf"),
        .package(path: "../BigInt"),
    ],
    targets: [
        .target(
            name: "SwiftATV",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "BigInt", package: "BigInt"),
            ],
            exclude: [
                "swift-protobuf-config.json",
                "Protocols/MRP/Protobuf",
            ]
        ),
        .testTarget(
            name: "SwiftATVTests",
            dependencies: ["SwiftATV"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
