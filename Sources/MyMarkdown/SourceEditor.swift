import AppKit
import SwiftUI

@MainActor
final class EditorSession {
    private weak var textView: MarkdownTextView?
    private var documentID: String?
    private var isApplyingExternalChange = false

    func attach(_ textView: MarkdownTextView) {
        self.textView = textView
    }

    func synchronize(documentID: String, text: String, selection: NSRange, kind: DocumentKind) {
        guard let textView else { return }
        textView.kind = kind

        let documentChanged = self.documentID != documentID
        if documentChanged || (textView.string != text && !isApplyingExternalChange) {
            isApplyingExternalChange = true
            let visibleOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            textView.string = text
            let safeLocation = min(selection.location, (text as NSString).length)
            let safeLength = min(selection.length, (text as NSString).length - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            if let visibleOrigin { textView.enclosingScrollView?.contentView.scroll(to: visibleOrigin) }
            if documentChanged { textView.undoManager?.removeAllActions() }
            isApplyingExternalChange = false
        }
        self.documentID = documentID
    }

    func apply(_ action: FormattingAction, kind: DocumentKind) {
        guard let textView, textView.kind == kind else { return }
        let selectedRange = textView.selectedRange()
        let source = textView.string as NSString
        let safeLocation = min(selectedRange.location, source.length)
        let safeLength = min(selectedRange.length, source.length - safeLocation)
        let range = NSRange(location: safeLocation, length: safeLength)
        let replacement = EditorTextTransform.replacement(for: action, kind: kind, selectedText: source.substring(with: range))
        textView.replaceText(in: range, with: replacement.text, selection: NSRange(location: safeLocation + replacement.cursorOffset, length: safeLength == 0 ? 0 : range.length))
    }
}

final class MarkdownTextView: NSTextView {
    var kind: DocumentKind = .markdown

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard kind == .markdown, selection.length == 0 else {
            super.insertNewline(sender)
            return
        }

        let source = string as NSString
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = source.substring(with: lineRange)
        let insideCodeFence = MarkdownWritingBehavior.isInsideCodeFence(text: string, before: lineRange.location)

        switch MarkdownWritingBehavior.lineBreakAction(for: line, insideCodeFence: insideCodeFence) {
        case .normal:
            super.insertNewline(sender)
        case .continueWith(let prefix):
            replaceText(in: selection, with: "\n\(prefix)", selection: NSRange(location: selection.location + prefix.utf16.count + 1, length: 0))
        case .removePrefix(let prefixLength):
            replaceText(in: NSRange(location: lineRange.location, length: prefixLength), with: "", selection: NSRange(location: lineRange.location, length: 0))
        }
    }

    override func insertTab(_ sender: Any?) {
        guard kind == .markdown, let edit = selectedLineEdit(), MarkdownWritingBehavior.isListOrQuote(edit.lines) else {
            super.insertTab(sender)
            return
        }
        replaceText(in: edit.range, with: MarkdownWritingBehavior.indent(edit.lines), selection: NSRange(location: selectedRange().location + 2, length: selectedRange().length))
    }

    override func insertBacktab(_ sender: Any?) {
        guard kind == .markdown, let edit = selectedLineEdit(), MarkdownWritingBehavior.isListOrQuote(edit.lines) else {
            super.insertBacktab(sender)
            return
        }
        let replacement = MarkdownWritingBehavior.outdent(edit.lines)
        let removed = max(0, edit.lines.utf16.count - replacement.utf16.count)
        replaceText(in: edit.range, with: replacement, selection: NSRange(location: max(edit.range.location, selectedRange().location - min(2, removed)), length: selectedRange().length))
    }

    override func paste(_ sender: Any?) {
        guard kind == .markdown,
              let html = NSPasteboard.general.string(forType: .html),
              !html.isEmpty else {
            super.paste(sender)
            return
        }
        let markdown = MarkdownPasteConverter.convertHTML(html)
        guard !markdown.isEmpty else {
            super.paste(sender)
            return
        }
        insertText(markdown, replacementRange: selectedRange())
    }

    func replaceText(in range: NSRange, with replacement: String, selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }

    private func selectedLineEdit() -> (range: NSRange, lines: String)? {
        let source = string as NSString
        let selection = selectedRange()
        guard source.length > 0 else { return nil }
        let start = source.lineRange(for: NSRange(location: min(selection.location, source.length - 1), length: 0)).location
        let endLocation = min(source.length - 1, max(0, NSMaxRange(selection) - 1))
        let endRange = source.lineRange(for: NSRange(location: endLocation, length: 0))
        let range = NSRange(location: start, length: NSMaxRange(endRange) - start)
        return (range, source.substring(with: range))
    }
}

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let kind: DocumentKind
    let documentID: String
    let session: EditorSession

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 24, height: 22)
        textView.font = editorFont
        textView.backgroundColor = .textBackgroundColor

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.parent = self
        textView.font = editorFont
        session.attach(textView)
        session.synchronize(documentID: documentID, text: text, selection: selection, kind: kind)
    }

    private var editorFont: NSFont {
        kind == .html ? .monospacedSystemFont(ofSize: 15, weight: .regular) : .systemFont(ofSize: 17, weight: .regular)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        init(_ parent: SourceEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.selection = view.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange()
        }
    }
}
