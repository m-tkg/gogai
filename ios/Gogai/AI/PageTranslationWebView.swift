import SwiftUI
import WebKit

/// TranslatedPageModel の WKWebView を SwiftUI に橋渡しする。
/// システム翻訳(TranslatedPageView)・基盤モデル翻訳(FMTranslatedPageView)の両方が使う。
struct PageTranslationWebView: UIViewRepresentable {
    @ObservedObject var model: TranslatedPageModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
