// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lightdown",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .target(
            name: "LightdownKit",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Lightdown",
            dependencies: ["LightdownKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Test suite as a plain executable: XCTest and Swift Testing don't run with
        // the Command Line Tools alone. Run with `swift run LightdownChecks`.
        .executableTarget(
            name: "LightdownChecks",
            dependencies: ["LightdownKit"],
            path: "Checks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
