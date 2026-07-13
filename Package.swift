// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkPadCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MarkPadCore", targets: ["MarkPadCore"])],
    targets: [
        .target(
            name: "MarkPadCore",
            path: "Sources",
            exclude: ["AppState.swift", "ContentView.swift", "EditorView.swift", "Markdown.swift", "MarkPadApp.swift", "NotesImport.swift", "PreviewView.swift"],
            sources: ["WriterSupport.swift"]
        ),
        .testTarget(name: "MarkPadCoreTests", dependencies: ["MarkPadCore"], path: "Tests/MarkPadCoreTests")
    ]
)
