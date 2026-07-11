import Foundation
import AppKit

/// One-shot importer that copies Apple Notes into the vault as Markdown files,
/// organized by their Notes folder. Uses Apple Events, so macOS shows a
/// one-time "MarkPad wants to control Notes" permission prompt.
enum NotesImporter {

    struct ImportResult {
        var imported = 0
        var skipped = 0
    }

    static func importNotes(into root: URL) throws -> ImportResult {
        let script = """
        set out to {}
        tell application "Notes"
            repeat with theNote in notes
                try
                    set folderName to name of container of theNote
                on error
                    set folderName to "Notes"
                end try
                set end of out to {folderName, name of theNote, body of theNote}
            end repeat
        end tell
        return out
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw importError("Couldn't build the import script.")
        }
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw importError(message)
        }

        let destRoot = root.appendingPathComponent("Apple Notes Import", isDirectory: true)
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)

        var result = ImportResult()
        let count = descriptor.numberOfItems
        guard count > 0 else { return result }

        for i in 1...count {
            guard let item = descriptor.atIndex(i),
                  item.numberOfItems >= 3,
                  let folderName = item.atIndex(1)?.stringValue,
                  let noteName = item.atIndex(2)?.stringValue,
                  let body = item.atIndex(3)?.stringValue else {
                result.skipped += 1
                continue
            }

            let folder = destRoot.appendingPathComponent(sanitize(folderName), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            var fileName = sanitize(noteName)
            if fileName.isEmpty { fileName = "Untitled" }
            var dest = folder.appendingPathComponent(fileName + ".md")
            var suffix = 2
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = folder.appendingPathComponent("\(fileName) \(suffix).md")
                suffix += 1
            }

            let markdown = htmlToMarkdown(body)
            do {
                try markdown.write(to: dest, atomically: true, encoding: .utf8)
                result.imported += 1
            } catch {
                result.skipped += 1
            }
        }
        return result
    }

    // MARK: - HTML -> Markdown (Apple Notes bodies are simple HTML)

    static func htmlToMarkdown(_ html: String) -> String {
        var s = html

        func replace(_ pattern: String, _ template: String) {
            if let re = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                                withTemplate: template)
            }
        }

        replace(#"<h1[^>]*>(.*?)</h1>"#, "\n# $1\n")
        replace(#"<h2[^>]*>(.*?)</h2>"#, "\n## $1\n")
        replace(#"<h3[^>]*>(.*?)</h3>"#, "\n### $1\n")
        replace(#"<(b|strong)[^>]*>(.*?)</\1>"#, "**$2**")
        replace(#"<(i|em)[^>]*>(.*?)</\1>"#, "*$2*")
        replace(#"<li[^>]*>(.*?)</li>"#, "- $1\n")
        replace(#"<(ul|ol)[^>]*>"#, "\n")
        replace(#"</(ul|ol)>"#, "\n")
        replace(#"<blockquote[^>]*>(.*?)</blockquote>"#, "\n> $1\n")
        replace(#"<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, "[$2]($1)")
        replace(#"<br\s*/?>"#, "\n")
        replace(#"</div>\s*<div[^>]*>"#, "\n")
        replace(#"</?div[^>]*>"#, "\n")
        replace(#"</p>"#, "\n\n")
        replace(#"<[^>]+>"#, "")

        // Decode common entities
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ]
        for (entity, char) in entities {
            s = s.replacingOccurrences(of: entity, with: char)
        }

        // Tidy whitespace
        if let re = try? NSRegularExpression(pattern: #"\n{3,}"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                            withTemplate: "\n\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func sanitize(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 80 { s = String(s.prefix(80)) }
        return s
    }

    private static func importError(_ message: String) -> NSError {
        NSError(domain: "MarkPad.NotesImport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
