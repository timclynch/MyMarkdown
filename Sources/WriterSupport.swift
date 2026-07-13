import Foundation

enum ItemNameRules {
    static func normalizedName(_ rawName: String, keepingExtension fileExtension: String? = nil) throws -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fileExtension, name.lowercased().hasSuffix(".\(fileExtension.lowercased())") {
            name.removeLast(fileExtension.count + 1)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !name.isEmpty else { throw ItemNameRuleError.empty }
        guard name != ".", name != ".." else { throw ItemNameRuleError.reserved }
        guard !name.contains("/"), !name.contains(":"), !name.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw ItemNameRuleError.invalidCharacters
        }
        return name
    }

    static func renamedURL(from oldURL: URL, baseName: String, isDirectory: Bool) -> URL {
        var url = oldURL.deletingLastPathComponent().appendingPathComponent(baseName, isDirectory: isDirectory)
        if !isDirectory, !oldURL.pathExtension.isEmpty {
            url = url.appendingPathExtension(oldURL.pathExtension)
        }
        return url
    }

    static func remappedURL(_ url: URL?, from oldURL: URL, to newURL: URL) -> URL? {
        guard let url else { return nil }
        let oldPath = oldURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == oldPath || path.hasPrefix(oldPath + "/") else { return url }
        return URL(fileURLWithPath: newURL.standardizedFileURL.path + String(path.dropFirst(oldPath.count)))
    }
}

enum ItemNameRuleError: LocalizedError {
    case empty
    case reserved
    case invalidCharacters

    var errorDescription: String? {
        switch self {
        case .empty: return "Enter a name."
        case .reserved: return "That name is reserved by macOS."
        case .invalidCharacters: return "Names cannot contain /, :, or null characters."
        }
    }
}

enum MarkdownWriter {
    enum LineBreakAction: Equatable {
        case normal
        case continueWith(String)
        case removePrefix(Int)
    }

    static func lineBreakAction(for line: String, insideCodeFence: Bool) -> LineBreakAction {
        guard !insideCodeFence, let match = listMatch(in: line) else { return .normal }
        return match.remainder.trimmingCharacters(in: .whitespaces).isEmpty
            ? .removePrefix(match.prefix.utf16.count)
            : .continueWith(continuedPrefix(from: match.prefix))
    }

    static func isInsideCodeFence(_ text: String, before location: Int) -> Bool {
        let length = min(location, (text as NSString).length)
        let prefix = (text as NSString).substring(to: length)
        let fences = prefix.components(separatedBy: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        }
        return fences.count % 2 == 1
    }

    static func isListOrQuote(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains { listMatch(in: $0) != nil }
    }

    static func indent(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
    }

    static func outdent(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line)
        }.joined(separator: "\n")
    }

    static func markdownFromHTML(_ html: String) -> String {
        var value = html
        value = replace(value, pattern: "(?is)<h([1-6])[^>]*>(.*?)</h\\1>") { groups in
            let level = Int(groups[1]) ?? 1
            return "\n\n\(String(repeating: "#", count: level)) \(groups[2])\n\n"
        }
        value = replace(value, pattern: "(?is)<ol[^>]*>(.*?)</ol>") { groups in
            return orderedListMarkdown(groups[1])
        }
        value = replace(value, pattern: "(?is)<li[^>]*>\\s*(<input[^>]*>)?\\s*(.*?)</li>") { groups in
            let input = groups[1].lowercased()
            let marker = input.contains("checkbox") ? (input.contains("checked") ? "- [x] " : "- [ ] ") : "- "
            return "\n\(marker)\(groups[2])"
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

    private static func listMatch(in line: String) -> (prefix: String, remainder: String)? {
        guard let expression = try? NSRegularExpression(pattern: "^(\\s*(?:[-*+] |\\d+\\. |> |- \\[ ?[xX]? ?\\] ))(.*)$") else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let prefix = Range(match.range(at: 1), in: line),
              let remainder = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[prefix]), String(line[remainder]))
    }

    private static func continuedPrefix(from prefix: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "^(\\s*)(\\d+)\\.\\s+$"),
              let match = expression.firstMatch(in: prefix, range: NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)),
              let indentRange = Range(match.range(at: 1), in: prefix),
              let numberRange = Range(match.range(at: 2), in: prefix),
              let number = Int(prefix[numberRange]) else { return prefix }
        return "\(prefix[indentRange])\(number + 1). "
    }

    private static func orderedListMarkdown(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "(?is)<li[^>]*>\\s*(.*?)</li>") else { return value }
        let matches = expression.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value))
        return matches.enumerated().compactMap { index, match in
            guard let range = Range(match.range(at: 1), in: value) else { return nil }
            return "\n\(index + 1). \(value[range])"
        }.joined()
    }

    private static func replace(_ value: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        var result = value
        let matches = expression.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)).reversed()
        for match in matches {
            let groups = (0..<match.numberOfRanges).map { index -> String in
                guard let range = Range(match.range(at: index), in: result) else { return "" }
                return String(result[range])
            }
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(groups))
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
