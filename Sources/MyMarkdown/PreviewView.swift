import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let source: String
    let kind: DocumentKind

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = kind == .markdown
            ? MarkdownRenderer.document(from: source)
            : HTMLWrapper.document(from: source)
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var lastHTML = ""
    }
}

private enum HTMLWrapper {
    static func document(from source: String) -> String {
        if source.range(of: "<html", options: .caseInsensitive) != nil {
            return source
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(PreviewStyle.css)</style></head><body>\(source)</body></html>
        """
    }
}

private enum MarkdownRenderer {
    static func document(from markdown: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(PreviewStyle.css)</style></head>
        <body>\(body(from: markdown))</body></html>
        """
    }

    private static func body(from markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output: [String] = []
        var paragraph: [String] = []
        var listType: String?
        var inCode = false
        var codeLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                if let type = listType { output.append("</\(type)>"); listType = nil }
                if inCode {
                    output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll()
                }
                inCode.toggle()
                index += 1
                continue
            }

            if inCode {
                codeLines.append(line)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                if let type = listType { output.append("</\(type)>"); listType = nil }
                index += 1
                continue
            }

            if isTableHeader(lines: lines, index: index) {
                flushParagraph()
                if let type = listType { output.append("</\(type)>"); listType = nil }
                let headers = tableCells(line)
                output.append("<table><thead><tr>" + headers.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>")
                index += 2
                while index < lines.count, lines[index].contains("|") && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    let cells = tableCells(lines[index])
                    output.append("<tr>" + cells.map { "<td>\(inline($0))</td>" }.joined() + "</tr>")
                    index += 1
                }
                output.append("</tbody></table>")
                continue
            }

            if let heading = headingParts(trimmed) {
                flushParagraph()
                if let type = listType { output.append("</\(type)>"); listType = nil }
                output.append("<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                if let type = listType { output.append("</\(type)>"); listType = nil }
                output.append("<hr>")
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                if let type = listType { output.append("</\(type)>"); listType = nil }
                output.append("<blockquote>\(inline(String(trimmed.dropFirst(2))))</blockquote>")
                index += 1
                continue
            }

            if let item = unorderedItem(trimmed) {
                flushParagraph()
                if listType != "ul" {
                    if let type = listType { output.append("</\(type)>") }
                    output.append("<ul>")
                    listType = "ul"
                }
                output.append("<li>\(checklist(item))</li>")
                index += 1
                continue
            }

            if let item = orderedItem(trimmed) {
                flushParagraph()
                if listType != "ol" {
                    if let type = listType { output.append("</\(type)>") }
                    output.append("<ol>")
                    listType = "ol"
                }
                output.append("<li>\(inline(item))</li>")
                index += 1
                continue
            }

            if let type = listType { output.append("</\(type)>"); listType = nil }
            paragraph.append(trimmed)
            index += 1
        }

        if inCode {
            output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
        }
        flushParagraph()
        if let type = listType { output.append("</\(type)>") }
        return output.joined(separator: "\n")
    }

    private static func headingParts(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func unorderedItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), dot < line.endIndex else { return nil }
        let number = line[..<dot]
        let after = line.index(after: dot)
        guard !number.isEmpty, number.allSatisfy(\.isNumber), after < line.endIndex, line[after] == " " else { return nil }
        return String(line[line.index(after: after)...])
    }

    private static func checklist(_ item: String) -> String {
        if item.hasPrefix("[ ] ") {
            return "<input type=\"checkbox\" disabled> \(inline(String(item.dropFirst(4))))"
        }
        if item.lowercased().hasPrefix("[x] ") {
            return "<input type=\"checkbox\" checked disabled> \(inline(String(item.dropFirst(4))))"
        }
        return inline(item)
    }

    private static func isTableHeader(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard separator.contains("|") else { return false }
        return tableCells(separator).allSatisfy { cell in
            let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
            return value.isEmpty && cell.contains("-")
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func inline(_ source: String) -> String {
        var value = escape(source)
        value = replace(value, pattern: "!\\[([^]]*)\\]\\(([^ )]+)\\)", template: "<img src=\"$2\" alt=\"$1\">")
        value = replace(value, pattern: "\\[([^]]+)\\]\\(([^ )]+)\\)", template: "<a href=\"$2\">$1</a>")
        value = replace(value, pattern: "`([^`]+)`", template: "<code>$1</code>")
        value = replace(value, pattern: "\\*\\*([^*]+)\\*\\*", template: "<strong>$1</strong>")
        value = replace(value, pattern: "__([^_]+)__", template: "<strong>$1</strong>")
        value = replace(value, pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", template: "<em>$1</em>")
        value = replace(value, pattern: "(?<!_)_([^_]+)_(?!_)", template: "<em>$1</em>")
        value = replace(value, pattern: "~~([^~]+)~~", template: "<del>$1</del>")
        return value
    }

    private static func replace(_ input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }

    private static func escape(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

}

private enum PreviewStyle {
    static let css = """
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; }
    body {
      max-width: 820px; margin: 0 auto; padding: 38px 44px 80px;
      font: 17px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      color: #1f2328; background: transparent; overflow-wrap: break-word;
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 .55em; color: #111418; }
    h1 { font-size: 2.15em; border-bottom: 1px solid #d8dee4; padding-bottom: .28em; }
    h2 { font-size: 1.55em; border-bottom: 1px solid #e5e9ed; padding-bottom: .22em; }
    h3 { font-size: 1.25em; }
    p { margin: 0 0 1em; }
    a { color: #0a66c2; text-decoration: none; }
    a:hover { text-decoration: underline; }
    ul, ol { padding-left: 1.6em; }
    li { margin: .25em 0; }
    blockquote { margin: 1.2em 0; padding: .15em 1em; color: #59636e; border-left: 4px solid #9aa7b4; }
    code { font: .9em ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(127,127,127,.13); padding: .18em .35em; border-radius: 5px; }
    pre { background: rgba(127,127,127,.12); padding: 16px; border-radius: 9px; overflow: auto; }
    pre code { background: none; padding: 0; }
    table { width: 100%; border-collapse: collapse; margin: 1.2em 0; }
    th, td { padding: 8px 11px; border: 1px solid #c9d1d9; text-align: left; }
    th { background: rgba(127,127,127,.1); }
    img { max-width: 100%; border-radius: 8px; }
    hr { border: 0; border-top: 1px solid #d8dee4; margin: 2em 0; }
    input[type=checkbox] { width: 1.05em; height: 1.05em; vertical-align: -.1em; }
    @media (prefers-color-scheme: dark) {
      body { color: #d8dee4; }
      h1, h2, h3, h4, h5, h6 { color: #f0f3f6; }
      h1, h2, hr { border-color: #3d444d; }
      a { color: #58a6ff; }
      blockquote { color: #9da7b1; }
      th, td { border-color: #3d444d; }
    }
    """
}
