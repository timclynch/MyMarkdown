import SwiftUI
import AppKit

/// Bridges toolbar/menu formatting actions to the live NSTextView.
final class FormatController {
    weak var textView: NSTextView?

    func wrapSelection(_ prefix: String, _ suffix: String) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let source = textView.string as NSString
        let selected = range.length > 0 ? source.substring(with: range) : ""
        let replacement = prefix + selected + suffix
        replace(textView, range: range, with: replacement,
                selection: selected.isEmpty
                    ? NSRange(location: range.location + (prefix as NSString).length, length: 0)
                    : NSRange(location: range.location, length: (replacement as NSString).length))
    }

    /// Adds or removes a prefix (like "# " or "- ") on every selected line.
    func toggleLinePrefix(_ prefix: String) {
        guard let textView else { return }
        let source = textView.string as NSString
        let lineRange = source.lineRange(for: textView.selectedRange())
        let block = source.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) || $0.isEmpty }
        let newLines = lines.map { line -> String in
            if line.isEmpty { return line }
            if allPrefixed { return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line }
            if prefix.hasPrefix("#") {
                return prefix + Markdown.regexReplace(line, #"^#{1,6}\s+"#, "")
            }
            return prefix + line
        }
        var replacement = newLines.joined(separator: "\n")
        if hadTrailingNewline { replacement += "\n" }
        replace(textView, range: lineRange, with: replacement,
                selection: NSRange(location: lineRange.location, length: (replacement as NSString).length))
    }

    func insertSnippet(_ snippet: String) {
        guard let textView else { return }
        let range = textView.selectedRange()
        replace(textView, range: range, with: snippet,
                selection: NSRange(location: range.location + (snippet as NSString).length, length: 0))
    }

    private func replace(_ textView: NSTextView, range: NSRange, with replacement: String, selection: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(selection)
        textView.window?.makeFirstResponder(textView)
    }
}

/// Native plain-text editor with Markdown-safe writing helpers.
final class WriterTextView: NSTextView {
    var mode: DocMode = .markdown

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard mode == .markdown, selection.length == 0, (string as NSString).length > 0 else {
            super.insertNewline(sender)
            return
        }
        let source = string as NSString
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = source.substring(with: lineRange)
        let insideCodeFence = MarkdownWriter.isInsideCodeFence(string, before: lineRange.location)
        switch MarkdownWriter.lineBreakAction(for: line, insideCodeFence: insideCodeFence) {
        case .normal:
            super.insertNewline(sender)
        case .continueWith(let prefix):
            replaceText(in: selection, with: "\n\(prefix)", selection: NSRange(location: selection.location + prefix.utf16.count + 1, length: 0))
        case .removePrefix(let prefixLength):
            replaceText(in: NSRange(location: lineRange.location, length: prefixLength), with: "", selection: NSRange(location: lineRange.location, length: 0))
        }
    }

    override func insertTab(_ sender: Any?) {
        guard mode == .markdown,
              let block = selectedLineBlock(),
              !MarkdownWriter.isInsideCodeFence(string, before: block.range.location),
              MarkdownWriter.isListOrQuote(block.text) else {
            super.insertTab(sender)
            return
        }
        let selection = selectedRange()
        replaceText(in: block.range, with: MarkdownWriter.indent(block.text),
                    selection: NSRange(location: selection.location + 2, length: selection.length))
    }

    override func insertBacktab(_ sender: Any?) {
        guard mode == .markdown,
              let block = selectedLineBlock(),
              !MarkdownWriter.isInsideCodeFence(string, before: block.range.location),
              MarkdownWriter.isListOrQuote(block.text) else {
            super.insertBacktab(sender)
            return
        }
        let replacement = MarkdownWriter.outdent(block.text)
        let removed = max(0, block.text.utf16.count - replacement.utf16.count)
        let selection = selectedRange()
        replaceText(in: block.range, with: replacement,
                    selection: NSRange(location: max(block.range.location, selection.location - min(2, removed)), length: selection.length))
    }

    override func paste(_ sender: Any?) {
        guard mode == .markdown,
              let html = NSPasteboard.general.string(forType: .html),
              !html.isEmpty else {
            super.paste(sender)
            return
        }
        let markdown = MarkdownWriter.markdownFromHTML(html)
        guard !markdown.isEmpty else {
            super.paste(sender)
            return
        }
        insertText(markdown, replacementRange: selectedRange())
    }

    private func replaceText(in range: NSRange, with replacement: String, selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }

    private func selectedLineBlock() -> (range: NSRange, text: String)? {
        let source = string as NSString
        guard source.length > 0 else { return nil }
        let selection = selectedRange()
        let start = source.lineRange(for: NSRange(location: min(selection.location, source.length - 1), length: 0)).location
        let end = min(source.length - 1, max(0, NSMaxRange(selection) - 1))
        let endRange = source.lineRange(for: NSRange(location: end, length: 0))
        let range = NSRange(location: start, length: NSMaxRange(endRange) - start)
        return (range, source.substring(with: range))
    }
}

/// SwiftUI bridge that keeps the native text view and its undo history stable
/// while the file model autosaves in the background.
struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: FormatController
    let mode: DocMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let textView = WriterTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.mode = mode
        textView.string = text
        scrollView.documentView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? WriterTextView else { return }
        context.coordinator.parent = self
        controller.textView = textView
        textView.mode = mode
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        init(_ parent: EditorTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
