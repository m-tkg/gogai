import SwiftUI
import WebKit

struct HTMLContentView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedHTML != styledHTML {
            context.coordinator.loadedHTML = styledHTML
            webView.loadHTMLString(styledHTML, baseURL: nil)
        }
    }

    private var styledHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: -apple-system, sans-serif;
            font-size: 17px;
            line-height: 1.7;
            margin: 0; padding: 0;
            color: #000;
            word-break: break-word;
          }
          @media (prefers-color-scheme: dark) {
            body { color: #eee; }
            a { color: #4af; }
          }
          img { max-width: 100%; height: auto; border-radius: 6px; }
          pre, code { font-size: 14px; overflow-x: auto; }
          a { color: #007aff; }
          p { margin: 0 0 1em; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLContentView
        var loadedHTML: String?

        init(_ parent: HTMLContentView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height
                    }
                }
            }
        }
    }
}
