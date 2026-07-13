import Foundation

struct EditorReplacement {
    let text: String
    let cursorOffset: Int
}

enum EditorTextTransform {
    static func replacement(for action: FormattingAction, kind: DocumentKind, selectedText: String) -> EditorReplacement {
        kind == .markdown ? markdownReplacement(action, selectedText) : htmlReplacement(action, selectedText)
    }

    private static func markdownReplacement(_ action: FormattingAction, _ selected: String) -> EditorReplacement {
        switch action {
        case .heading: EditorReplacement(text: "## " + (selected.isEmpty ? "Heading" : selected), cursorOffset: 3)
        case .bold: EditorReplacement(text: "**" + (selected.isEmpty ? "bold text" : selected) + "**", cursorOffset: 2)
        case .italic: EditorReplacement(text: "_" + (selected.isEmpty ? "italic text" : selected) + "_", cursorOffset: 1)
        case .bulletedList: prefixedLines(selected, prefix: "- ")
        case .numberedList: numberedLines(selected)
        case .checklist: prefixedLines(selected, prefix: "- [ ] ")
        case .quote: prefixedLines(selected, prefix: "> ")
        case .link: EditorReplacement(text: "[" + (selected.isEmpty ? "link text" : selected) + "](https://)", cursorOffset: 1)
        case .code: selected.contains("\n")
            ? EditorReplacement(text: "```\n\(selected)\n```", cursorOffset: 4)
            : EditorReplacement(text: "`" + (selected.isEmpty ? "code" : selected) + "`", cursorOffset: 1)
        }
    }

    private static func htmlReplacement(_ action: FormattingAction, _ selected: String) -> EditorReplacement {
        let content = selected.isEmpty ? "text" : selected
        return switch action {
        case .heading: EditorReplacement(text: "<h2>\(content)</h2>", cursorOffset: 4)
        case .bold: EditorReplacement(text: "<strong>\(content)</strong>", cursorOffset: 8)
        case .italic: EditorReplacement(text: "<em>\(content)</em>", cursorOffset: 4)
        case .bulletedList: EditorReplacement(text: "<ul>\n  <li>\(content)</li>\n</ul>", cursorOffset: 11)
        case .numberedList: EditorReplacement(text: "<ol>\n  <li>\(content)</li>\n</ol>", cursorOffset: 11)
        case .checklist: EditorReplacement(text: "<label><input type=\"checkbox\"> \(content)</label>", cursorOffset: 38)
        case .quote: EditorReplacement(text: "<blockquote>\(content)</blockquote>", cursorOffset: 12)
        case .link: EditorReplacement(text: "<a href=\"https://\">\(content)</a>", cursorOffset: 19)
        case .code: EditorReplacement(text: "<code>\(content)</code>", cursorOffset: 6)
        }
    }

    private static func prefixedLines(_ selected: String, prefix: String) -> EditorReplacement {
        let source = selected.isEmpty ? "List item" : selected
        return EditorReplacement(
            text: source.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }.joined(separator: "\n"),
            cursorOffset: prefix.utf16.count
        )
    }

    private static func numberedLines(_ selected: String) -> EditorReplacement {
        let source = selected.isEmpty ? "List item" : selected
        let result = source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        return EditorReplacement(text: result, cursorOffset: 3)
    }
}

enum MarkdownWritingBehavior {
    enum LineBreakAction: Equatable {
        case normal
        case continueWith(String)
        case removePrefix(Int)
    }

    static func lineBreakAction(for line: String, insideCodeFence: Bool) -> LineBreakAction {
        guard !insideCodeFence, let match = listMatch(in: line) else { return .normal }
        return match.remainder.trimmingCharacters(in: .whitespaces).isEmpty
            ? .removePrefix(match.prefix.utf16.count)
            : .continueWith(match.prefix)
    }

    static func isInsideCodeFence(text: String, before location: Int) -> Bool {
        let length = min(location, (text as NSString).length)
        let prefix = (text as NSString).substring(to: length)
        return prefix.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count % 2 == 1
    }

    static func isListOrQuote(_ line: String) -> Bool {
        listMatch(in: line) != nil
    }

    static func indent(_ lines: String) -> String {
        lines.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
    }

    static func outdent(_ lines: String) -> String {
        lines.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line)
        }.joined(separator: "\n")
    }

    private static func listMatch(in line: String) -> (prefix: String, remainder: String)? {
        guard let expression = try? NSRegularExpression(pattern: "^(\\s*(?:[-*+] \\[?[ xX]?\\]? ?|\\d+\\. |> ))(.*)$") else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let prefixRange = Range(match.range(at: 1), in: line),
              let remainderRange = Range(match.range(at: 2), in: line) else { return nil }
        let prefix = String(line[prefixRange])
        let normalizedPrefix: String
        if prefix.trimmingCharacters(in: .whitespaces).hasPrefix("- [") {
            normalizedPrefix = prefix
        } else {
            normalizedPrefix = prefix
        }
        return (normalizedPrefix, String(line[remainderRange]))
    }
}

enum MarkdownPasteConverter {
    static func convertHTML(_ html: String) -> String {
        var value = html
        value = replace(value, pattern: "(?is)<h([1-6])[^>]*>(.*?)</h\\1>") { match in
            let level = Int(match[1]) ?? 1
            return "\n\n\(String(repeating: "#", count: level)) \(match[2])\n\n"
        }
        value = replace(value, pattern: "(?is)<li[^>]*>\\s*(<input[^>]*>)?\\s*(.*?)</li>") { match in
            let input = match[1].lowercased()
            let marker = input.contains("checkbox") ? (input.contains("checked") ? "- [x] " : "- [ ] ") : "- "
            return "\n\(marker)\(match[2])"
        }
        value = replace(value, pattern: "(?is)<a[^>]*href=[\\\"']([^\\\"']+)[\\\"'][^>]*>(.*?)</a>") { "[\($0[2])](\($0[1]))" }
        value = replace(value, pattern: "(?is)<(?:strong|b)[^>]*>(.*?)</(?:strong|b)>") { "**\($0[1])**" }
        value = replace(value, pattern: "(?is)<(?:em|i)[^>]*>(.*?)</(?:em|i)>") { "*\($0[1])*" }
        value = replace(value, pattern: "(?is)<br\\s*/?>") { _ in "\n" }
        value = replace(value, pattern: "(?is)</(?:p|div|section|article|ul|ol|blockquote)>") { _ in "\n\n" }
        value = replace(value, pattern: "(?is)<[^>]+>") { _ in "" }
        value = decodeEntities(value)
        value = value.replacingOccurrences(of: "\r\n", with: "\n")
        value = value.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ value: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let matches = expression.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)).reversed()
        var result = value
        for match in matches {
            let values = (0..<match.numberOfRanges).map { index -> String in
                guard let range = Range(match.range(at: index), in: result) else { return "" }
                return String(result[range])
            }
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(values))
        }
        return result
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
