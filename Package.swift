// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lightdown",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .executableTarget(
            name: "Lightdown",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
