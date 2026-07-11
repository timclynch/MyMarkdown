import SwiftUI
import WebKit

/// Live preview pane. Loads a styled shell page once, then swaps the body
/// content via JavaScript so the scroll position survives while typing.
struct PreviewWebView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        context.coordinator.webView = webView
        webView.loadHTMLString(Self.shell, baseURL: nil)
        context.coordinator.apply(html)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(html)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var ready = false
        private var pending: String?
        private var lastApplied: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let p = pending { push(p) }
        }

        // Open clicked links in the user's browser instead of the preview pane.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func apply(_ html: String) {
            guard html != lastApplied else { return }
            lastApplied = html
            if ready { push(html) } else { pending = html }
        }

        private func push(_ html: String) {
            pending = nil
            guard let webView,
                  let data = try? JSONEncoder().encode([html]),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("document.getElementById('c').innerHTML = \(json)[0];",
                                       completionHandler: nil)
        }
    }

    static let shell = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      :root { color-scheme: light dark; }
      body {
        font: 15px/1.65 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        max-width: 46em; margin: 0 auto; padding: 26px 34px 60px;
        color: #1d1d1f; background: transparent;
        -webkit-text-size-adjust: 100%;
      }
      @media (prefers-color-scheme: dark) {
        body { color: #e8e8ed; }
        a { color: #6cb2ff; }
        h1, h2 { border-bottom-color: rgba(255,255,255,.18); }
      }
      h1, h2, h3, h4 { line-height: 1.3; margin: 1.3em 0 .5em; font-weight: 650; }
      h1 { font-size: 1.9em; } h2 { font-size: 1.45em; } h3 { font-size: 1.17em; }
      h1, h2 { border-bottom: 1px solid rgba(127,127,127,.28); padding-bottom: .25em; }
      p { margin: .65em 0; }
      a { color: #0969da; text-decoration: none; }
      a:hover { text-decoration: underline; }
      code { font: 12.5px ui-monospace, "SF Mono", Menlo, monospace;
             background: rgba(127,127,127,.16); padding: 2px 5px; border-radius: 4px; }
      pre { background: rgba(127,127,127,.13); padding: 14px 16px; border-radius: 8px;
            overflow-x: auto; }
      pre code { background: none; padding: 0; }
      blockquote { border-left: 3px solid rgba(127,127,127,.45); margin: .8em 0;
                   padding: .1em 0 .1em 14px; color: rgba(127,127,127,.95); }
      blockquote p { margin: .3em 0; }
      ul, ol { padding-left: 1.5em; margin: .5em 0; }
      li { margin: .18em 0; }
      hr { border: none; border-top: 1px solid rgba(127,127,127,.35); margin: 1.6em 0; }
      table { border-collapse: collapse; margin: .8em 0; }
      th, td { border: 1px solid rgba(127,127,127,.38); padding: 6px 13px; }
      th { background: rgba(127,127,127,.12); }
      img { max-width: 100%; border-radius: 6px; }
      input[type=checkbox] { margin-right: 6px; }
    </style>
    </head>
    <body><div id="c"></div></body>
    </html>
    """
}
