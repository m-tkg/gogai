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
    /// 原文表示中かどうか（訳文 ⇄ 原文のトグル状態）
    @Published private(set) var isShowingOriginal = false

    /// extractTexts 時点の原文（index = ノード index）
    private var originalTexts: [String] = []
    /// 適用済みの訳文（key = ノード index）
    private var translations: [Int: String] = [:]

    var hasTranslations: Bool { !translations.isEmpty }

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
        let texts = result as? [String] ?? []
        originalTexts = texts
        translations = [:]
        isShowingOriginal = false
        return texts
    }

    /// index 番目のテキストノードの中身だけを訳文に差し替える（タグ・画像は不変）
    func applyTranslation(at index: Int, text: String) async {
        // Why: 訳文の引用符・改行・バックスラッシュで JS が壊れないよう
        // JSON エンコード経由で安全に文字列リテラル化する
        guard let data = try? JSONEncoder().encode([text]),
              let jsonArray = String(data: data, encoding: .utf8) else { return }
        let script = "window.__gogaiApply(\(index), (\(jsonArray))[0]); true;"
        _ = try? await webView.evaluateJavaScript(script)
        translations[index] = text
        translatedCount += 1
    }

    // MARK: - 原文 ⇄ 訳文のトグル

    /// 翻訳済みノードを原文表示に戻す
    func showOriginal() async {
        let indices = translations.keys.sorted()
        await bulkApply(indices: indices, texts: indices.compactMap { originalTexts.indices.contains($0) ? originalTexts[$0] : nil })
        isShowingOriginal = true
    }

    /// 原文表示から訳文表示に戻す
    func showTranslation() async {
        let indices = translations.keys.sorted()
        await bulkApply(indices: indices, texts: indices.compactMap { translations[$0] })
        isShowingOriginal = false
    }

    private struct BulkApplyPayload: Encodable {
        let i: [Int]
        let t: [String]
    }

    /// 複数ノードを1回の JS 実行でまとめて書き換える
    private func bulkApply(indices: [Int], texts: [String]) async {
        guard !indices.isEmpty, indices.count == texts.count,
              let data = try? JSONEncoder().encode(BulkApplyPayload(i: indices, t: texts)),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.__gogaiApplyAll(\(json)); true;"
        _ = try? await webView.evaluateJavaScript(script)
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
      window.__gogaiApplyAll = function(p) {
        for (let k = 0; k < p.i.length; k++) {
          const n = window.__gogaiNodes[p.i[k]];
          if (n) { n.nodeValue = p.t[k]; }
        }
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
