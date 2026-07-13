import Foundation
import XCTest
@testable import MyMarkdown

final class MyMarkdownTests: XCTestCase {
    func testDocumentNameValidationKeepsExpectedExtension() throws {
        XCTAssertEqual(try ItemNameValidator.normalizedBaseName("Project Notes.md", fileExtension: "md"), "Project Notes")
        XCTAssertEqual(try ItemNameValidator.normalizedBaseName("Project Notes", fileExtension: "md"), "Project Notes")
        XCTAssertThrowsError(try ItemNameValidator.normalizedBaseName("   "))
        XCTAssertThrowsError(try ItemNameValidator.normalizedBaseName("Projects/2026"))
    }

    func testFolderMoveRemapsSelectedChild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldFolder = root.appendingPathComponent("Old Project", isDirectory: true)
        let oldChild = oldFolder.appendingPathComponent("Notes.md")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try "# Notes".write(to: oldChild, atomically: true, encoding: .utf8)
        let newFolder = LibraryItemOperations.destinationURL(for: oldFolder, baseName: "New Project", isDirectory: true)
        try LibraryItemOperations.moveItem(at: oldFolder, to: newFolder)

        let remapped = LibraryItemOperations.remappedURL(oldChild, movingFrom: oldFolder, to: newFolder)
        XCTAssertEqual(remapped?.path, newFolder.appendingPathComponent("Notes.md").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFolder.appendingPathComponent("Notes.md").path))
    }

    func testMarkdownPasteConvertsCommonRichText() {
        let html = "<h2>Plan</h2><p>Use <strong>Markdown</strong> with <a href=\"https://example.com\">a link</a>.</p><ul><li>First</li><li><input type=\"checkbox\" checked>Done</li></ul>"
        let markdown = MarkdownPasteConverter.convertHTML(html)

        XCTAssertTrue(markdown.contains("## Plan"))
        XCTAssertTrue(markdown.contains("**Markdown**"))
        XCTAssertTrue(markdown.contains("[a link](https://example.com)"))
        XCTAssertTrue(markdown.contains("- First"))
        XCTAssertTrue(markdown.contains("- [x] Done"))
    }

    func testMarkdownListContinuationAndCodeFenceProtection() {
        XCTAssertEqual(MarkdownWritingBehavior.lineBreakAction(for: "- Build it", insideCodeFence: false), .continueWith("- "))
        XCTAssertEqual(MarkdownWritingBehavior.lineBreakAction(for: "- ", insideCodeFence: false), .removePrefix(2))
        XCTAssertEqual(MarkdownWritingBehavior.lineBreakAction(for: "- literal", insideCodeFence: true), .normal)
        XCTAssertEqual(MarkdownWritingBehavior.indent("- One\n- Two"), "  - One\n  - Two")
        XCTAssertEqual(MarkdownWritingBehavior.outdent("  - One\n  - Two"), "- One\n- Two")
    }

    func testFormattingTransformUsesMarkdownSyntax() {
        let replacement = EditorTextTransform.replacement(for: .bold, kind: .markdown, selectedText: "idea")
        XCTAssertEqual(replacement.text, "**idea**")
        XCTAssertEqual(replacement.cursorOffset, 2)
    }
}
