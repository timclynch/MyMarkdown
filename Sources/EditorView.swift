import SwiftUI
import AppKit

/// Bridges toolbar/menu formatting actions to the live NSTextView.
final class FormatController {
    weak var textView: NSTextView?

    func wrapSelection(_ prefix: String, _ suffix: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = range.length > 0 ? ns.substring(with: range) : ""
        let replacement = prefix + selected + suffix
        guard tv.shouldChangeText(in: range, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        if selected.isEmpty {
            tv.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: 0))
        } else {
            tv.setSelectedRange(NSRange(location: range.location, length: (replacement as NSString).length))
        }
        focus()
    }

    /// Adds or removes a prefix (like "# " or "- ") on every selected line.
    func toggleLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        let block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) || $0.isEmpty }
        let newLines = lines.map { line -> String in
            if line.isEmpty { return line }
            if allPrefixed {
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
            }
            // Strip any existing heading prefix before applying a heading
            if prefix.hasPrefix("#") {
                let stripped = Markdown.regexReplace(line, #"^#{1,6}\s+"#, "")
                return prefix + stripped
            }
            return prefix + line
        }
        var replacement = newLines.joined(separator: "\n")
        if hadTrailingNewline { replacement += "\n" }
        guard tv.shouldChangeText(in: lineRange, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: lineRange, with: replacement)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
        focus()
    }

    func insertSnippet(_ snippet: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        guard tv.shouldChangeText(in: range, replacementString: snippet) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: snippet)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + (snippet as NSString).length, length: 0))
        focus()
    }

    private func focus() {
        if let tv = textView { tv.window?.makeFirstResponder(tv) }
    }
}

/// Plain-text NSTextView wrapper tuned for writing Markdown/HTML:
/// smart quotes and auto-substitutions off, monospaced-friendly font, undo on.
struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: FormatController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.textContainerInset = NSSize(width: 18, height: 16)
        tv.autoresizingMask = [.width]
        tv.string = text
        scrollView.hasVerticalScroller = true
        controller.textView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        controller.textView = tv
        if tv.string != text {
            tv.string = text
            tv.scrollToBeginningOfDocument(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        init(_ parent: EditorTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
