// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CaliperSampleApp",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "CaliperSampleApp",
            targets: ["CaliperSampleApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/kibotu/Orchard", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CaliperSampleApp",
            dependencies: ["Orchard"],
            path: "Sources"
        )
    ]
)

