import SwiftUI
import WebKit

struct HTMLContentView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "heightObserver")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightObserver")
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
        <body>\(html)
        <script>
          new ResizeObserver(function() {
            window.webkit.messageHandlers.heightObserver.postMessage(document.body.scrollHeight);
          }).observe(document.body);
        </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLContentView
        var loadedHTML: String?

        init(_ parent: HTMLContentView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(webView)
        }

        func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { result, _ in
                if let height = result as? Double, height > 0 {
                    DispatchQueue.main.async {
                        self.parent.height = CGFloat(height)
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightObserver",
                  let height = message.body as? Double,
                  height > 0 else { return }
            DispatchQueue.main.async {
                self.parent.height = CGFloat(height)
            }
        }
    }
}
