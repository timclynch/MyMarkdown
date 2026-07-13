// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyMarkdown",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MyMarkdown", targets: ["MyMarkdown"])
    ],
    targets: [
        .executableTarget(
            name: "MyMarkdown",
            path: "Sources/MyMarkdown"
        ),
        .testTarget(
            name: "MyMarkdownTests",
            dependencies: ["MyMarkdown"],
            path: "Tests/MyMarkdownTests"
        )
    ]
)
