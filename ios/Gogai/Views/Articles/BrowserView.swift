import SwiftUI

#if targetEnvironment(macCatalyst)
import WebKit

struct BrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = BrowserModel()

    var body: some View {
        NavigationStack {
            BrowserWebView(model: browser)
                .ignoresSafeArea()
                .navigationTitle(browser.title.isEmpty ? url.host() ?? "" : browser.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            browser.webView.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!browser.canGoBack)

                        Button {
                            browser.webView.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!browser.canGoForward)

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
        .frame(minWidth: 800, idealWidth: 1100, maxWidth: .infinity, minHeight: 600, idealHeight: 750, maxHeight: .infinity)
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

#else
import SafariServices

// iOS/iPadOS: SFSafariViewController（Safari 拡張・広告ブロック対応）
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
#endif
