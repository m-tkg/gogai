import Foundation
import WebKit

/// レイアウト保持のページ内翻訳を行う WKWebView のモデル。
/// DOM のテキストノードを文単位に分割して span で包み、訳文を文ごとに書き戻すことで
/// 画像・タグ構造・CSS を変えずに文字だけを翻訳する。
/// 訳文で表示する文の割合(mixRatio)を持ち、残りは原文のまま表示する(文単位ミックス)。
/// 各文はページ上でタップすると原文 ⇄ 訳文を個別に切り替えられる(切り替えはページ側 JS が持つ)。
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
    /// 訳文で表示する文の割合(0〜100)
    @Published private(set) var mixRatio: Int

    /// extractTexts 時点の原文(index = 文の通し番号、前後の空白を除いた文)
    private var sentences: [String] = []
    /// 適用済みの訳文(key = 文 index)
    private var translations: [Int: String] = [:]
    /// 混ぜ直しのたびに進めるオフセット(どの文を訳文にするかの位相をずらす)
    private var mixOffset = 0

    var hasTranslations: Bool { !translations.isEmpty }
    /// 訳文として表示する文の index 集合(現在の割合・オフセットから算出)
    var translatedIndices: Set<Int> {
        Set(sentences.indices.filter { TranslationMix.isTranslated(index: $0, ratio: mixRatio, offset: mixOffset) })
    }

    let webView: WKWebView

    init(mixRatio: Int = TranslationMix.maxRatio) {
        self.mixRatio = TranslationMix.clamp(mixRatio)
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) {
        status = .loading
        webView.load(URLRequest(url: url))
    }

    /// テスト用にも使う(loadHTMLString でも didFinish が呼ばれる)
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

    /// ページ内の翻訳対象テキストノードを抽出し、文単位に分割して span で包む。
    /// 返り値は文書順の文(前後の空白を除いたもの)で、index がそのまま文の通し番号になる。
    func extractTexts() async throws -> [String] {
        let result = try await webView.evaluateJavaScript(Self.extractScript)
        let nodeTexts = result as? [String] ?? []
        let pieces = nodeTexts.map { SentenceSplitter.split($0) }
        translations = [:]
        translatedCount = 0
        sentences = pieces.flatMap { $0 }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !sentences.isEmpty,
           let data = try? JSONEncoder().encode(pieces),
           let json = String(data: data, encoding: .utf8) {
            _ = try? await webView.evaluateJavaScript("window.__gogaiSplit(\(json)); true;")
        }
        await applyMix()
        return sentences
    }

    /// index 番目の文の訳文を書き戻す(その文が訳文表示の対象なら即座に画面に反映される)
    func applyTranslation(at index: Int, text: String) async {
        await bulkSetTranslations(indices: [index], texts: [text])
        translations[index] = text
        translatedCount += 1
    }

    /// サーバーに保存済みの訳文を復元し、一括で書き戻す(FMTranslatedPageView の再表示時に使用)。
    /// key は文 index。
    func restoreTranslations(_ restored: [Int: String]) async {
        guard !restored.isEmpty else { return }
        for (index, text) in restored {
            translations[index] = text
        }
        await bulkSetTranslations(indices: Array(restored.keys), texts: Array(restored.values))
    }

    // MARK: - ミックス割合

    /// 訳文で表示する文の割合を変更し、全文の表示を割り当て直す(手動トグルはリセットされる)
    func setMixRatio(_ ratio: Int) async {
        let clamped = TranslationMix.clamp(ratio)
        guard clamped != mixRatio else { return }
        mixRatio = clamped
        await applyMix()
    }

    /// 同じ割合のまま、どの文を訳文にするかを混ぜ直す
    func reshuffle() async {
        mixOffset += 1
        await applyMix()
    }

    private struct SetShowPayload: Encodable {
        let i: [Int]
        let s: [Bool]
    }

    /// 現在の割合・オフセットから各文の表示フラグを算出してページに送る
    private func applyMix() async {
        guard !sentences.isEmpty else { return }
        let indices = Array(sentences.indices)
        let flags = indices.map { TranslationMix.isTranslated(index: $0, ratio: mixRatio, offset: mixOffset) }
        guard let data = try? JSONEncoder().encode(SetShowPayload(i: indices, s: flags)),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = try? await webView.evaluateJavaScript("window.__gogaiSetShow(\(json)); true;")
    }

    private struct SetTranslationsPayload: Encodable {
        let i: [Int]
        let t: [String]
    }

    /// 複数の文の訳文を 1 回の JS 実行でまとめて保持・描画する。
    /// Why: 訳文の引用符・改行・バックスラッシュで JS が壊れないよう JSON エンコード経由で渡す
    private func bulkSetTranslations(indices: [Int], texts: [String]) async {
        guard !indices.isEmpty, indices.count == texts.count,
              let data = try? JSONEncoder().encode(SetTranslationsPayload(i: indices, t: texts)),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = try? await webView.evaluateJavaScript("window.__gogaiSetTr(\(json)); true;")
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

    /// script / style / noscript / code / pre / textarea は翻訳対象から除外する。
    /// Android の `assets/translator/extract.js` と同一内容を保つこと。
    private static let extractScript = #"""
    (function() {
      // 再実行時(再翻訳)は前回の span を原文のテキストノードに戻してから走査し直す
      if (window.__gogaiSents && window.__gogaiSents.length > 0) {
        const parents = new Set();
        for (const s of window.__gogaiSents) {
          const parent = s.span.parentNode;
          if (!parent) { continue; }
          parent.replaceChild(document.createTextNode(s.src), s.span);
          parents.add(parent);
        }
        parents.forEach(function(p) { p.normalize(); });
      }
      window.__gogaiNodes = [];
      window.__gogaiSents = [];
      // 文(sentence)の表示を更新する。show && 訳あり なら訳文、それ以外は原文。
      // 原文の前後の空白は訳文表示でも保つ(文間の区切り空白を失わないため)。
      function render(s) {
        const showTr = s.show && s.tr !== null;
        let text = s.src;
        if (showTr) {
          const lead = s.src.match(/^\s*/)[0];
          const trail = s.src.match(/\s*$/)[0];
          text = lead + s.tr + trail;
        }
        if (s.span.textContent !== text) { s.span.textContent = text; }
        s.span.classList.toggle('gogai-sent--tr', showTr);
      }
      function ensureStyle() {
        if (document.getElementById('gogai-sent-style')) { return; }
        const style = document.createElement('style');
        style.id = 'gogai-sent-style';
        style.textContent = '.gogai-sent{cursor:pointer}' +
          '.gogai-sent--tr{text-decoration:underline dotted;text-decoration-color:rgba(128,128,128,.55);' +
          'text-decoration-thickness:1px;text-underline-offset:.2em}';
        (document.head || document.documentElement).appendChild(style);
      }
      // pieces[nodeIndex] = そのノードを文単位に分割した文字列配列(連結すると元の nodeValue に一致する)。
      // 各文を span で包み、文書順の通し番号(= 文 index)で window.__gogaiSents に保持する。
      window.__gogaiSplit = function(pieces) {
        const sents = window.__gogaiSents = [];
        ensureStyle();
        for (let i = 0; i < pieces.length; i++) {
          const n = window.__gogaiNodes[i];
          const parts = pieces[i];
          if (!n || !n.parentNode || !parts || parts.length === 0) { continue; }
          const frag = document.createDocumentFragment();
          for (let k = 0; k < parts.length; k++) {
            const span = document.createElement('span');
            span.className = 'gogai-sent';
            span.textContent = parts[k];
            const s = { span: span, src: parts[k], tr: null, show: false };
            span.setAttribute('data-gogai-sent', String(sents.length));
            // タップで原文 ⇄ 訳文を切り替える(訳が届いていない文は通常のクリックとして扱う)
            span.addEventListener('click', function(e) {
              if (s.tr === null) { return; }
              e.preventDefault();
              e.stopPropagation();
              s.show = !s.show;
              render(s);
            }, true);
            sents.push(s);
            frag.appendChild(span);
          }
          n.parentNode.replaceChild(frag, n);
        }
        return sents.length;
      };
      // p = {i: [文index...], t: [訳文...]} 訳文を保持し、表示フラグに従って描画する
      window.__gogaiSetTr = function(p) {
        for (let k = 0; k < p.i.length; k++) {
          const s = window.__gogaiSents[p.i[k]];
          if (s) { s.tr = p.t[k]; render(s); }
        }
      };
      // p = {i: [文index...], s: [bool...]} 訳文を表示するかどうかのフラグを一括設定する
      window.__gogaiSetShow = function(p) {
        for (let k = 0; k < p.i.length; k++) {
          const s = window.__gogaiSents[p.i[k]];
          if (s) { s.show = !!p.s[k]; render(s); }
        }
      };
      // SVG/MATH は span を挿入すると描画されなくなるため対象外(XML 要素は tagName が小文字なので大文字化して比較)
      const reject = ['SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE', 'TEXTAREA', 'SVG', 'MATH'];
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function(node) {
          let el = node.parentElement;
          while (el) {
            if (reject.includes(el.tagName.toUpperCase())) { return NodeFilter.FILTER_REJECT; }
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
    """#
}
