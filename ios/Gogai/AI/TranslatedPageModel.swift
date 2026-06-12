import Foundation
import WebKit

/// レイアウト保持のページ内翻訳を行う WKWebView のモデル。
/// DOM のテキストノードだけを抽出し、訳文をノード単位で書き戻すことで
/// 画像・タグ構造・CSS を一切変えずに文字だけを翻訳する。
@MainActor
final class TranslatedPageModel: NSObject, ObservableObject, WKNavigationDelegate {
    enum Status: Equatable {
        case loading
        case ready
        case translating
        case done
        case failed(String)
    }

    @Published private(set) var status: Status = .loading
    @Published private(set) var translatedCount = 0
    @Published private(set) var totalCount = 0

    let webView: WKWebView

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) {
        status = .loading
        webView.load(URLRequest(url: url))
    }

    /// テスト用にも使う（loadHTMLString でも didFinish が呼ばれる）
    func loadHTML(_ html: String) {
        status = .loading
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status = .ready
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        status = .failed(error.localizedDescription)
    }

    // MARK: - テキスト抽出・書き戻し

    /// ページ内の翻訳対象テキストノードを抽出し、ノード参照をページ側
    /// （window.__gogaiNodes）に保持する。返り値の index がそのままノードの index。
    func extractTexts() async throws -> [String] {
        let result = try await webView.evaluateJavaScript(Self.extractScript)
        return result as? [String] ?? []
    }

    /// index 番目のテキストノードの中身だけを訳文に差し替える（タグ・画像は不変）
    func applyTranslation(at index: Int, text: String) async {
        // Why: 訳文の引用符・改行・バックスラッシュで JS が壊れないよう
        // JSON エンコード経由で安全に文字列リテラル化する
        guard let data = try? JSONEncoder().encode([text]),
              let jsonArray = String(data: data, encoding: .utf8) else { return }
        let script = "window.__gogaiApply(\(index), (\(jsonArray))[0]); true;"
        _ = try? await webView.evaluateJavaScript(script)
        translatedCount += 1
    }

    func beginTranslating(total: Int) {
        totalCount = total
        translatedCount = 0
        status = .translating
    }

    func markDone() {
        status = .done
    }

    func markFailed(_ message: String) {
        status = .failed(message)
    }

    /// script / style / noscript / code / pre / textarea は翻訳対象から除外する
    private static let extractScript = """
    (function() {
      window.__gogaiNodes = [];
      window.__gogaiApply = function(i, t) {
        const n = window.__gogaiNodes[i];
        if (n) { n.nodeValue = t; }
      };
      const reject = ['SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE', 'TEXTAREA'];
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function(node) {
          let el = node.parentElement;
          while (el) {
            if (reject.includes(el.tagName)) { return NodeFilter.FILTER_REJECT; }
            el = el.parentElement;
          }
          return node.nodeValue && node.nodeValue.trim().length > 1
            ? NodeFilter.FILTER_ACCEPT
            : NodeFilter.FILTER_SKIP;
        }
      });
      const texts = [];
      let n;
      while ((n = walker.nextNode())) {
        window.__gogaiNodes.push(n);
        texts.push(n.nodeValue);
      }
      return texts;
    })();
    """
}
