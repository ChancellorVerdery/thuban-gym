// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThubanGymCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ThubanGymCore", targets: ["ThubanGymCore"]),
    ],
    targets: [
        .target(
            name: "ThubanGymCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThubanGymCoreTests",
            dependencies: ["ThubanGymCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
