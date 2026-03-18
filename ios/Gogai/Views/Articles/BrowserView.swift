import SwiftUI
import SafariServices

// SFSafariViewController 実装（Safari 拡張・広告ブロック対応）
// WKWebView 実装に戻す場合は末尾の WKBrowserView を参照

struct BrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SafariView(url: url, onDismiss: { dismiss() })
            .ignoresSafeArea()
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}

// MARK: - WKWebView 実装（ロールバック用）
// BrowserView を下記に差し替えることで元の実装に戻せる
/*
import WebKit

struct BrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = BrowserModel()

    var body: some View {
        NavigationStack {
            BrowserWebView(model: browser)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(browser.title.isEmpty ? url.host() ?? "" : browser.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            browser.webView.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!browser.canGoBack)

                        Spacer()

                        Button {
                            browser.webView.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!browser.canGoForward)

                        Spacer()

                        Button {
                            if browser.isLoading {
                                browser.webView.stopLoading()
                            } else {
                                browser.webView.reload()
                            }
                        } label: {
                            Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                        }
                    }
                }
        }
        .onAppear {
            browser.webView.load(URLRequest(url: url))
        }
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    let webView: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: config)
    }
}

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        model.webView.navigationDelegate = context.coordinator
        model.webView.allowsBackForwardNavigationGestures = true
        return model.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let model: BrowserModel

        init(model: BrowserModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                model.isLoading = true
                model.canGoBack = webView.canGoBack
                model.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                model.isLoading = false
                model.title = webView.title ?? ""
                model.canGoBack = webView.canGoBack
                model.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                model.isLoading = false
            }
        }
    }
}
*/
