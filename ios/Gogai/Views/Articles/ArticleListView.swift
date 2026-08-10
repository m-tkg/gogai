import SwiftUI

struct ArticleListView: View {
    let feedId: Int?
    let groupId: Int?
    @Binding var selectedArticle: Article?
    var onArticleSelected: ((Article) -> Void)?
    var onStockTap: (() -> Void)?

    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var stockStore: StockStore

    @State private var showMarkAllConfirm = false
    /// true になると .task の再フェッチをスキップする
    /// ArticleDetailView から戻るとき（ビュー再表示）は再フェッチしない
    /// フィード一覧から記事一覧を新たに開いたときは新インスタンスなので false にリセットされる
    @State private var hasAppeared = false

    private var secretFeedIds: Set<Int> {
        // 全記事表示時のみシークレットグループのフィードを除外する
        guard feedId == nil, groupId == nil else { return [] }
        return groupStore.secretFeedIds(in: feedStore.feeds)
    }

    private var displayedArticles: [Article] {
        var result = articleStore.articles
        if !secretFeedIds.isEmpty {
            result = result.filter { !secretFeedIds.contains($0.feed_id) }
        }
        return result
    }

    var body: some View {
        List(selection: $selectedArticle) {
            ForEach(displayedArticles) { article in
                ArticleRowView(article: article)
                    .tag(article)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedArticle = article
                        onArticleSelected?(article)
                        if !article.isRead {
                            Task { await articleStore.markAsRead(id: article.id) }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await articleStore.toggleRead(article) }
                        } label: {
                            Label(
                                article.isRead ? "未読にする" : "既読にする",
                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }
                        .tint(article.isRead ? .orange : .blue)
                    }
                    // 先に宣言したボタンほど端に配置されるため、浅いスワイプではストックだけが見え、
                    // 深く引くと like が現れる
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            addToStock(article)
                        } label: {
                            Label("ストックに入れる", systemImage: "tray.and.arrow.down")
                        }
                        .tint(.blue)

                        Button {
                            Task { await articleStore.toggleLike(article) }
                        } label: {
                            Label(
                                article.isLiked ? "like を外す" : "like",
                                systemImage: article.isLiked ? "hand.thumbsup.slash" : "hand.thumbsup"
                            )
                        }
                        .tint(article.isLiked ? .gray : .pink)
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(listTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("ソート") {
                        ForEach(ArticleSortOrder.allCases, id: \.self) { order in
                            Button {
                                articleStore.sortOrder = order
                                Task { await articleStore.fetchArticles(feedId: feedId, groupId: groupId, includeSecret: groupStore.showSecretGroups) }
                            } label: {
                                if articleStore.sortOrder == order {
                                    Label(order.label, systemImage: "checkmark")
                                } else {
                                    Text(order.label)
                                }
                            }
                        }
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body)
                        Image(systemName: articleStore.sortOrder.badgeIconName)
                            .font(.system(size: 9, weight: .semibold))
                            .offset(x: 6, y: 5)
                    }
                    .padding(.trailing, 4)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMarkAllConfirm = true
                } label: {
                    Image(systemName: "envelope.open.fill")
                }
                .disabled(displayedArticles.allSatisfy { $0.isRead })
                .confirmationDialog("表示中の記事をすべて既読にしますか？", isPresented: $showMarkAllConfirm, titleVisibility: .visible) {
                    Button("すべて既読にする", role: .destructive) {
                        Task { await articleStore.markAllAsRead() }
                    }
                    Button("キャンセル", role: .cancel) {}
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FilterFooterView(filter: $articleStore.filter, onStockTap: onStockTap)
        }
        .onChange(of: articleStore.filter) { _, newVal in
            Task { await articleStore.fetchArticles(feedId: feedId, groupId: groupId, filter: newVal, includeSecret: groupStore.showSecretGroups) }
        }
        .overlay {
            if articleStore.isLoading {
                ProgressView()
            } else if displayedArticles.isEmpty {
                ContentUnavailableView("記事がありません", systemImage: "newspaper")
            }
        }
        .refreshable {
            _ = try? await feedStore.refreshAll()
        }
        .task {
            // 初回表示のみフェッチする
            // ArticleDetailView から戻る際は再フェッチしない（既読記事を消さないため）
            // フィード一覧から記事一覧を開き直した場合は新インスタンスなので hasAppeared=false
            guard !hasAppeared else { return }
            hasAppeared = true
            await articleStore.fetchArticles(feedId: feedId, groupId: groupId, includeSecret: groupStore.showSecretGroups)
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            let articles = displayedArticles
            guard !articles.isEmpty else { return .ignored }
            let delta = press.key == .downArrow ? 1 : -1
            if let current = selectedArticle,
               let idx = articles.firstIndex(where: { $0.id == current.id }) {
                let newIdx = max(0, min(articles.count - 1, idx + delta))
                guard newIdx != idx else { return .ignored }
                selectedArticle = articles[newIdx]
                Task { await articleStore.markAsRead(id: articles[newIdx].id) }
            } else {
                let newIdx = delta > 0 ? 0 : articles.count - 1
                selectedArticle = articles[newIdx]
                Task { await articleStore.markAsRead(id: articles[newIdx].id) }
            }
            return .handled
        }
        .onChange(of: feedId) { _, newId in
            Task { await articleStore.fetchArticles(feedId: newId, groupId: groupId, includeSecret: groupStore.showSecretGroups) }
        }
        .onChange(of: groupId) { _, newId in
            Task { await articleStore.fetchArticles(feedId: feedId, groupId: newId, includeSecret: groupStore.showSecretGroups) }
        }
        .onChange(of: groupStore.showSecretGroups) { _, newVal in
            Task { await articleStore.fetchArticles(feedId: feedId, groupId: groupId, includeSecret: newVal) }
        }
    }

    private var listTitle: String {
        if let feedId {
            return feedStore.feeds.first(where: { $0.id == feedId })?.title ?? "記事"
        }
        if groupId != nil { return "記事" }
        return "すべての記事"
    }

    /// 記事をストックに追加する(ストック元は所属グループ名)
    private func addToStock(_ article: Article) {
        guard let link = article.link else { return }
        let groupName = feedStore.feeds.first(where: { $0.id == article.feed_id })?.group_id
            .flatMap { groupId in groupStore.groups.first(where: { $0.id == groupId })?.name }
        Task { try? await stockStore.createStock(url: link, title: article.title, source: groupName ?? "未分類") }
    }
}
