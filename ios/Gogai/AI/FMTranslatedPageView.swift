import SwiftUI
import WebKit
import CryptoKit

/// サーバーに保存する翻訳セグメントの形式。
/// segments は stocks.translation の不透明な JSON としてそのまま保存・取得される。
struct FMTranslationPayload: Codable, Sendable {
    struct Segment: Codable, Sendable {
        /// ノード index
        let i: Int
        /// 原文の SHA256(ページが変化していないかの照合に使う)
        let h: String
        /// 訳文
        let t: String
    }
    let version: Int
    let segments: [Segment]
}

/// Foundation Model でレイアウト保持のページ内翻訳を行うビュー
/// (TranslatedPageView のシステム翻訳版に対する基盤モデル版)。
/// 翻訳結果はサーバーに保存し、再表示時は原文ハッシュが一致するノードだけ復元する
/// (ページが変化した箇所は原文のまま表示する)。
struct FMTranslatedPageView: View {
    let stock: Stock

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = TranslatedPageModel()
    @State private var hasStarted = false

    private var pageTitle: String { stock.title ?? stock.url }

    var body: some View {
        FMTranslatedPageWebView(model: model)
            .ignoresSafeArea()
            .overlay(alignment: .top) { statusBar }
            .overlay(alignment: .bottomTrailing) { floatingButtons }
            .onAppear {
                if let url = URL(string: stock.url) { model.load(url) }
            }
            .onChange(of: model.status) { _, newStatus in
                guard newStatus == .ready, !hasStarted else { return }
                hasStarted = true
                Task { await runTranslation() }
            }
    }

    private var floatingButtons: some View {
        VStack(spacing: 12) {
            CircleIconButton(
                systemName: model.isShowingOriginal ? "character.bubble" : "doc.plaintext",
                accessibilityLabel: model.isShowingOriginal ? "翻訳を表示" : "原文を表示",
                isEnabled: isToggleEnabled
            ) {
                Task {
                    if model.isShowingOriginal {
                        await model.showTranslation()
                    } else {
                        await model.showOriginal()
                    }
                }
            }
            CircleIconButton(
                systemName: "arrow.clockwise",
                accessibilityLabel: "再翻訳",
                isEnabled: isRetranslateEnabled
            ) {
                Task { await runTranslation(forceRetranslate: true) }
            }
            CircleIconButton(systemName: "xmark", accessibilityLabel: "閉じる") { dismiss() }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 70)
    }

    private var isToggleEnabled: Bool {
        model.status == .done && model.hasTranslations
    }

    private var isRetranslateEnabled: Bool {
        model.status == .done || isFailed
    }

    private var isFailed: Bool {
        if case .failed = model.status { return true }
        return false
    }

    @ViewBuilder
    private var statusBar: some View {
        switch model.status {
        case .loading:
            statusLabel("ページを読み込んでいます…", showsProgress: true)
        case .ready, .translating:
            statusLabel(
                model.totalCount > 0
                    ? "翻訳中… (\(model.translatedCount)/\(model.totalCount))"
                    : "翻訳の準備中…",
                showsProgress: true
            )
        case .failed(let message):
            statusLabel("翻訳に失敗しました: \(message)", showsProgress: false)
        case .done:
            EmptyView()
        }
    }

    private func statusLabel(_ text: String, showsProgress: Bool) -> some View {
        HStack(spacing: 8) {
            if showsProgress { ProgressView() }
            Text(text).font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 12)
    }

    // MARK: - 翻訳の実行・保存

    private func runTranslation(forceRetranslate: Bool = false) async {
        // オンデバイス AI は同時に1リクエストしか処理できないため、要約キューを一時停止し
        // 翻訳を優先する(#126 参照)。中断された要約はキュー再開時に最初からやり直される。
        stockStore.pauseSummaryQueueForTranslation()
        defer { stockStore.resumeSummaryQueueAfterTranslation() }
        // 翻訳中にバックグラウンドへ移っても継続する(システム猶予内)
        await BackgroundExecution.run(name: "Stock.translatePage") {
            await performTranslation(forceRetranslate: forceRetranslate)
        }
    }

    private func performTranslation(forceRetranslate: Bool) async {
        guard let generator = LocalAI.makeGenerator() else {
            model.markFailed("この端末ではローカル AI を利用できません(iOS 27 以上と Apple Intelligence の有効化が必要です)")
            return
        }
        do {
            let texts = try await model.extractTexts()
            guard !texts.isEmpty else {
                model.markDone()
                return
            }

            let savedPayload = forceRetranslate ? nil : await stockStore.fetchTranslation(id: stock.id)
            let savedSegments = Self.decodeSegments(savedPayload?.segments) ?? []
            let savedByIndex = Dictionary(uniqueKeysWithValues: savedSegments.map { ($0.i, $0) })

            // 原文ハッシュが一致するノードだけ復元し、それ以外(未保存・ページ変化)を翻訳対象にする
            var restored: [Int: String] = [:]
            var indicesToTranslate: [Int] = []
            for (index, text) in texts.enumerated() {
                if let segment = savedByIndex[index], segment.h == Self.hash(text) {
                    restored[index] = segment.t
                } else {
                    indicesToTranslate.append(index)
                }
            }
            if !restored.isEmpty {
                await model.restoreTranslations(restored)
            }

            var translatedNow: [Int: String] = [:]
            if !indicesToTranslate.isEmpty {
                model.beginTranslating(total: indicesToTranslate.count)
                let translator = FMPageTranslator(generator: generator)
                translatedNow = await translator.translate(texts: texts, indicesToTranslate: indicesToTranslate, pageTitle: pageTitle)
                for index in indicesToTranslate.sorted() {
                    guard let text = translatedNow[index] else { continue }
                    await model.applyTranslation(at: index, text: text)
                }
            }
            model.markDone()

            await save(texts: texts, restored: restored, translatedNow: translatedNow)
        } catch {
            model.markFailed(error.localizedDescription)
        }
    }

    private func save(texts: [String], restored: [Int: String], translatedNow: [Int: String]) async {
        let merged = restored.merging(translatedNow) { _, new in new }
        guard !merged.isEmpty else { return }
        let segments = merged.map { FMTranslationPayload.Segment(i: $0.key, h: Self.hash(texts[$0.key]), t: $0.value) }
        let payload = FMTranslationPayload(version: 1, segments: segments)
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else { return }
        try? await stockStore.saveTranslation(id: stock.id, segments: json)
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeSegments(_ json: String?) -> [FMTranslationPayload.Segment]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FMTranslationPayload.self, from: data).segments
    }
}

/// TranslatedPageModel の WKWebView を SwiftUI に橋渡しする
private struct FMTranslatedPageWebView: UIViewRepresentable {
    @ObservedObject var model: TranslatedPageModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
