// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "caliper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "caliper", targets: ["caliper"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        // All analysis logic lives here so it can be unit tested. The executable
        // target is only the ArgumentParser front end.
        .target(
            name: "CaliperCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            // d3 is vendored rather than fetched from a CDN so the generated report
            // opens offline, on an air-gapped CI runner, and from a downloaded
            // artifact. See Resources/d3.v7.min.js.
            resources: [
                .copy("Resources/d3.v7.min.js")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "caliper",
            dependencies: [
                "CaliperCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CaliperCoreTests",
            dependencies: ["CaliperCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
