import SwiftUI
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

// MARK: - Model

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

// MARK: - WebView

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
