import Foundation
import XCTest
@testable import MarkPadCore

final class MarkPadCoreTests: XCTestCase {
    func testDocumentNamesKeepTheirOriginalExtension() throws {
        XCTAssertEqual(try ItemNameRules.normalizedName("Release Notes.md", keepingExtension: "md"), "Release Notes")
        XCTAssertEqual(try ItemNameRules.normalizedName("Release Notes", keepingExtension: "md"), "Release Notes")
        XCTAssertThrowsError(try ItemNameRules.normalizedName("../secret"))
    }

    func testFolderRenameRemapsAnOpenChild() {
        let oldFolder = URL(fileURLWithPath: "/tmp/Old Project", isDirectory: true)
        let newFolder = URL(fileURLWithPath: "/tmp/New Project", isDirectory: true)
        let child = oldFolder.appendingPathComponent("Notes.md")
        XCTAssertEqual(ItemNameRules.remappedURL(child, from: oldFolder, to: newFolder)?.path,
                       newFolder.appendingPathComponent("Notes.md").path)
    }

    func testMarkdownWriterHandlesListsAndCodeFences() {
        XCTAssertEqual(MarkdownWriter.lineBreakAction(for: "- Plan", insideCodeFence: false), .continueWith("- "))
        XCTAssertEqual(MarkdownWriter.lineBreakAction(for: "9. Plan", insideCodeFence: false), .continueWith("10. "))
        XCTAssertEqual(MarkdownWriter.lineBreakAction(for: "- ", insideCodeFence: false), .removePrefix(2))
        XCTAssertEqual(MarkdownWriter.lineBreakAction(for: "- literal", insideCodeFence: true), .normal)
    }

    func testRichTextPasteBecomesMarkdown() {
        let html = "<h2>Plan</h2><p>Use <strong>Markdown</strong> with <a href=\"https://example.com\">a link</a>.</p><ul><li>First</li><li><input type=\"checkbox\" checked>Done</li></ul>"
        let markdown = MarkdownWriter.markdownFromHTML(html)
        XCTAssertTrue(markdown.contains("## Plan"))
        XCTAssertTrue(markdown.contains("**Markdown**"))
        XCTAssertTrue(markdown.contains("[a link](https://example.com)"))
        XCTAssertTrue(markdown.contains("- [x] Done"))
    }

    func testOrderedRichTextPasteBecomesNumberedMarkdown() {
        XCTAssertEqual(MarkdownWriter.markdownFromHTML("<ol><li>First</li><li>Second</li></ol>"),
                       "1. First\n2. Second")
    }
}
