import SwiftUI

/// サマリーの4セクション(何についての記事か/何の目的で書かれたか/
/// 筆者が一番伝えたいこと/要約)を表示する。パース失敗時は生テキストにフォールバックする。
private struct StockSummarySections: View {
    let summary: String

    var body: some View {
        if let parsed = StockSummary.parse(summary) {
            VStack(alignment: .leading, spacing: 16) {
                section(title: "何についての記事か", body: parsed.topic)
                section(title: "何の目的で書かれたか", body: parsed.purpose)
                section(title: "筆者が一番伝えたいこと", body: parsed.mainMessage)
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("要約")
                    ForEach(Array(parsed.summaryLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
            }
        } else {
            Text(summary)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(title)
            Text(body)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text("【\(title)】")
            .font(.headline)
            .foregroundStyle(Color.accentColor)
    }
}

/// フッターに並べるアイコン+キャプションのボタン(記事詳細ページの下部バーと同じスタイル)
private struct StockDetailFooterButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                }
                Text(label)
                    .font(.caption2)
            }
        }
        .foregroundStyle(isDestructive ? .red : .primary)
        .disabled(isDisabled)
    }
}

/// ストックの詳細(タイトル・ストック元・日付・サマリー)。
/// 操作ボタン(元記事・翻訳・要約生成・編集・削除)はフッターにまとめて表示する。
struct StockDetailView: View {
    let stock: Stock

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showBrowser = false
    @State private var showTranslation = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showShareSheet = false
    @State private var deleteError: Error?

    /// 要約の生成中/待機中はストアのキュー状態を見る(View のライフサイクルに依存しないため、
    /// 戻るボタンで離れてもキュー処理は継続する)。
    private var isGeneratingSummary: Bool {
        stockStore.currentlySummarizingStockId == currentStock.id || isQueued
    }

    private var isQueued: Bool {
        stockStore.pendingSummaryStockIds.contains(currentStock.id)
    }

    private var summaryError: String? {
        stockStore.summaryErrors[currentStock.id]
    }

    /// 翻訳を実行できる(または結果を再確認できる)条件:
    /// この端末で AI が使えるか、既に翻訳済みで結果が保存されているか
    private var canShowTranslation: Bool {
        LocalAI.isAvailable || currentStock.has_translation
    }

    private var currentStock: Stock {
        stockStore.stocks.first(where: { $0.id == stock.id }) ?? stock
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(currentStock.title ?? currentStock.url)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 12) {
                        Label(currentStock.source, systemImage: "folder")
                        Label(currentStock.stocked_at.displayDate, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()

                    summaryContent
                }
                .padding()
            }

            Divider()
            bottomBar
        }
        // 左スワイプで元記事(記事ページ)を開く(RSS 記事詳細ページと同じ操作)
        .onHorizontalSwipe(.left) {
            if URL(string: currentStock.url) != nil {
                showBrowser = true
            }
        }
        .navigationTitle("ストック")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showBrowser) {
            browserDestination
        }
        .navigationDestination(isPresented: $showTranslation) {
            FMTranslatedPageView(stock: currentStock)
        }
        .sheet(isPresented: $showEdit) {
            EditStockView(stock: currentStock)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = URL(string: currentStock.url) {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog("このストックを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                Task {
                    do {
                        try await stockStore.deleteStock(id: currentStock.id)
                        dismiss()
                    } catch {
                        deleteError = error
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("削除に失敗しました", isPresented: deleteErrorBinding) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError?.localizedDescription ?? "")
        }
    }

    /// 元記事(記事ページ)。
    /// iOS/iPadOS: 右下に閉じるボタンを重ね、右スワイプでも閉じられる(RSS 記事ページと同じ操作)
    /// macOS(Mac Catalyst): BrowserView 自身のツールバー(閉じる/戻る/進む/リロード)をそのまま使う
    @ViewBuilder
    private var browserDestination: some View {
        if let url = URL(string: currentStock.url) {
            #if targetEnvironment(macCatalyst)
            BrowserView(url: url, onClose: { showBrowser = false })
            #else
            BrowserView(url: url, onClose: { showBrowser = false })
                .overlay(alignment: .bottomTrailing) {
                    CircleIconButton(systemName: "xmark", accessibilityLabel: "閉じる") { showBrowser = false }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                }
                .toolbar(.hidden, for: .navigationBar)
                .onHorizontalSwipe(.right) { showBrowser = false }
            #endif
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let summary = currentStock.summary {
            StockSummarySections(summary: summary)
        } else if isGeneratingSummary {
            HStack(spacing: 8) {
                ProgressView()
                Text(isQueued ? "要約の順番待ちです…" : "要約を生成しています…")
            }
            .foregroundStyle(.secondary)
        } else if let summaryError {
            VStack(alignment: .leading, spacing: 4) {
                Label("要約の生成に失敗しました", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(summaryError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("要約はまだありません", systemImage: "text.badge.plus")
                .foregroundStyle(.secondary)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 24) {
            Spacer()
            if URL(string: currentStock.url) != nil {
                StockDetailFooterButton(icon: "square.and.arrow.up", label: "共有") { showShareSheet = true }
            }
            StockDetailFooterButton(
                icon: "sparkles",
                label: "要約",
                isLoading: isGeneratingSummary,
                isDisabled: currentStock.summary != nil || isGeneratingSummary || !LocalAI.isAvailable
            ) {
                stockStore.requestSummary(for: currentStock.id)
            }
            if canShowTranslation {
                StockDetailFooterButton(icon: "character.bubble", label: "翻訳") { showTranslation = true }
            }
            if let url = URL(string: currentStock.url) {
                StockDetailFooterButton(icon: "safari", label: "表示") { openURL(url) }
            }
            StockDetailFooterButton(icon: "pencil", label: "編集") { showEdit = true }
            StockDetailFooterButton(icon: "trash", label: "削除", isDestructive: true) { showDeleteConfirm = true }
            Spacer()
        }
        .padding(.vertical, 10)
        .background(.bar)
    }
}
