// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "amphitheatre",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "amphitheatre", targets: ["amphitheatre"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "amphitheatre",
            dependencies: [],
            resources: []
        )
    ]
)
