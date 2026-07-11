import AppKit
import SwiftUI

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let kind: DocumentKind

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 24, height: 22)
        textView.font = editorFont
        textView.string = text
        textView.backgroundColor = .textBackgroundColor

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let visible = scrollView.contentView.bounds
            textView.string = text
            textView.font = editorFont
            let safeLocation = min(selection.location, (text as NSString).length)
            let safeLength = min(selection.length, (text as NSString).length - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            scrollView.contentView.scroll(to: visible.origin)
        }
        if textView.font != editorFont { textView.font = editorFont }
    }

    private var editorFont: NSFont {
        if kind == .html { return .monospacedSystemFont(ofSize: 15, weight: .regular) }
        return NSFont.systemFont(ofSize: 17, weight: .regular)
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
