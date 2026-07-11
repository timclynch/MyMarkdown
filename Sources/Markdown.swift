import Foundation

// Lightweight Markdown -> HTML converter covering the GitHub-flavored
// subset people actually use: headings, lists (nested), task lists,
// fenced code, inline code, bold/italic/strikethrough, links, images,
// blockquotes, tables, and horizontal rules.
enum Markdown {

    static func toHTML(_ source: String) -> String {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var html: [String] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: "<br>")
            html.append("<p>\(joined)</p>")
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // skip closing fence
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                html.append("<pre><code\(cls)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            // Blank line
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Heading
            if let m = match(line, #"^(#{1,6})\s+(.*)$"#) {
                flushParagraph()
                let level = m[1].count
                html.append("<h\(level)>\(inline(escape(m[2])))</h\(level)>")
                i += 1
                continue
            }

            // Horizontal rule
            if match(trimmed, #"^(\*{3,}|-{3,}|_{3,})$"#) != nil {
                flushParagraph()
                html.append("<hr>")
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var inner = String(t.dropFirst())
                    if inner.hasPrefix(" ") { inner = String(inner.dropFirst()) }
                    quoted.append(inner)
                    i += 1
                }
                let innerHTML = toHTML(quoted.joined(separator: "\n"))
                html.append("<blockquote>\(innerHTML)</blockquote>")
                continue
            }

            // Table: header row + separator row
            if line.contains("|"), i + 1 < lines.count,
               match(lines[i + 1], #"^\s*\|?[\s:\-|]+\|?\s*$"#) != nil,
               lines[i + 1].contains("-") {
                flushParagraph()
                let header = tableCells(line)
                i += 2
                var rows: [[String]] = []
                while i < lines.count && lines[i].contains("|")
                        && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[i]))
                    i += 1
                }
                var t = "<table><thead><tr>"
                t += header.map { "<th>\(inline(escape($0)))</th>" }.joined()
                t += "</tr></thead><tbody>"
                for row in rows {
                    t += "<tr>" + row.map { "<td>\(inline(escape($0)))</td>" }.joined() + "</tr>"
                }
                t += "</tbody></table>"
                html.append(t)
                continue
            }

            // List (unordered or ordered, with indentation-based nesting)
            if match(line, #"^\s*([-*+]|\d+\.)\s+"#) != nil {
                flushParagraph()
                var items: [(indent: Int, ordered: Bool, text: String)] = []
                while i < lines.count, let m = match(lines[i], #"^(\s*)([-*+]|\d+\.)\s+(.*)$"#) {
                    let indentStr = m[1].replacingOccurrences(of: "\t", with: "  ")
                    let level = indentStr.count / 2
                    let ordered = m[2].hasSuffix(".")
                    items.append((min(level, 5), ordered, m[3]))
                    i += 1
                }
                html.append(renderList(items))
                continue
            }

            // Plain paragraph line
            paragraph.append(inline(escape(line)))
            i += 1
        }
        flushParagraph()
        return html.joined(separator: "\n")
    }

    // MARK: - List rendering

    private static func renderList(_ items: [(indent: Int, ordered: Bool, text: String)]) -> String {
        var out = ""
        var stack: [(indent: Int, tag: String)] = []

        func openList(_ indent: Int, _ ordered: Bool) {
            let tag = ordered ? "ol" : "ul"
            out += "<\(tag)>"
            stack.append((indent, tag))
        }
        func closeList() {
            if let top = stack.popLast() {
                out += "</li></\(top.tag)>"
            }
        }

        for (idx, item) in items.enumerated() {
            if stack.isEmpty {
                openList(item.indent, item.ordered)
            } else if item.indent > stack.last!.indent {
                openList(item.indent, item.ordered)
            } else {
                while stack.count > 1 && item.indent < stack.last!.indent {
                    closeList()
                }
                out += "</li>"
            }

            var text = item.text
            var checkbox = ""
            if text.hasPrefix("[ ] ") {
                checkbox = "<input type=\"checkbox\" disabled> "
                text = String(text.dropFirst(4))
            } else if text.lowercased().hasPrefix("[x] ") {
                checkbox = "<input type=\"checkbox\" checked disabled> "
                text = String(text.dropFirst(4))
            }
            out += "<li>\(checkbox)\(inline(escape(text)))"
            _ = idx
        }
        while !stack.isEmpty { closeList() }
        return out
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t = String(t.dropFirst()) }
        if t.hasSuffix("|") { t = String(t.dropLast()) }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Inline formatting

    static func inline(_ s: String) -> String {
        var text = s
        // Protect inline code spans from further formatting
        var codeSpans: [String] = []
        text = regexReplaceWithCapture(text, #"`([^`]+)`"#) { groups in
            codeSpans.append("<code>\(groups[1])</code>")
            return "\u{1}\(codeSpans.count - 1)\u{1}"
        }

        text = regexReplace(text, #"!\[([^\]]*)\]\(([^)\s]+)\)"#, "<img src=\"$2\" alt=\"$1\">")
        text = regexReplace(text, #"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>")
        text = regexReplace(text, #"\*\*([^\*]+)\*\*"#, "<strong>$1</strong>")
        text = regexReplace(text, #"__([^_]+)__"#, "<strong>$1</strong>")
        text = regexReplace(text, #"(?<![\*\w])\*([^\*\n]+)\*(?!\*)"#, "<em>$1</em>")
        text = regexReplace(text, #"(?<![_\w])_([^_\n]+)_(?!\w)"#, "<em>$1</em>")
        text = regexReplace(text, #"~~([^~]+)~~"#, "<del>$1</del>")

        // Restore code spans
        for (idx, span) in codeSpans.enumerated() {
            text = text.replacingOccurrences(of: "\u{1}\(idx)\u{1}", with: span)
        }
        return text
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Regex helpers

    private static func match(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            guard let r = Range(m.range(at: idx), in: s) else { return "" }
            return String(s[r])
        }
    }

    static func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                           withTemplate: template)
    }

    private static func regexReplaceWithCapture(_ s: String, _ pattern: String,
                                                _ transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        while let m = re.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            let groups = (0..<m.numberOfRanges).map { idx -> String in
                guard let r = Range(m.range(at: idx), in: result) else { return "" }
                return String(result[r])
            }
            guard let full = Range(m.range, in: result) else { break }
            result.replaceSubrange(full, with: transform(groups))
        }
        return result
    }
}
