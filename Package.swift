// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ComposeMergeClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "ComposeMergeClaimKit", targets: ["ComposeMergeClaimKit"]),
        .executable(name: "ComposeMergeClaimDemo", targets: ["ComposeMergeClaimDemo"])
    ],
    targets: [
        .target(name: "ComposeMergeClaimKit"),
        .executableTarget(
            name: "ComposeMergeClaimDemo",
            dependencies: ["ComposeMergeClaimKit"]
        ),
        .testTarget(
            name: "ComposeMergeClaimKitTests",
            dependencies: ["ComposeMergeClaimKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
