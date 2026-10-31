// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StreamMarkdown",
    // macOS so `swift test` runs on the build Mac; the views are UIKit and build for iOS only.
    platforms: [.iOS("27.1"), .macOS("27.0")],
    products: [
        .library(name: "StreamMarkdown", targets: ["StreamMarkdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3"),
    ],
    targets: [
        .target(
            name: "StreamMarkdown",
            dependencies: [.product(name: "Markdown", package: "swift-markdown"), "SwiftMath"]
        ),
        .testTarget(name: "StreamMarkdownTests", dependencies: ["StreamMarkdown"]),
    ]
)
