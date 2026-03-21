import SwiftUI

struct ArticleListView: View {
    let feedId: Int?
    let groupId: Int?
    @Binding var selectedArticle: Article?
    var onArticleSelected: ((Article) -> Void)?

    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var groupStore: GroupStore

    @State private var showMarkAllConfirm = false
    /// true になると .task の再フェッチをスキップする
    /// ArticleDetailView から戻るとき（ビュー再表示）は再フェッチしない
    /// フィード一覧から記事一覧を新たに開いたときは新インスタンスなので false にリセットされる
    @State private var hasAppeared = false

    private var secretFeedIds: Set<Int> {
        guard feedId == nil, groupId == nil, !groupStore.showSecretGroups else { return [] }
        return Set(feedStore.feeds.compactMap { feed -> Int? in
            guard let gid = feed.group_id,
                  groupStore.groups.first(where: { $0.id == gid })?.isSecret == true
            else { return nil }
            return feed.id
        })
    }

    private var displayedArticles: [Article] {
        var result = articleStore.articles
        if !secretFeedIds.isEmpty {
            result = result.filter { !secretFeedIds.contains($0.feed_id) }
        }
        if articleStore.summaryOnly {
            result = result.filter { $0.ai_summary != nil }
        }
        return result
    }

    var body: some View {
        List(selection: $selectedArticle) {
            ForEach(displayedArticles) { article in
                ArticleRowView(article: article)
                    .tag(article)
                    .onTapGesture {
                        selectedArticle = article
                        onArticleSelected?(article)
                        if !article.isRead {
                            Task { await articleStore.markAsRead(id: article.id) }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task {
                                if article.isRead {
                                    await articleStore.markAsUnread(id: article.id)
                                } else {
                                    await articleStore.markAsRead(id: article.id)
                                }
                            }
                        } label: {
                            Label(
                                article.isRead ? "未読にする" : "既読にする",
                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }
                        .tint(article.isRead ? .orange : .blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            Task { await articleStore.summarize(id: article.id) }
                        } label: {
                            Label("要約", systemImage: "sparkles")
                        }
                        .tint(.purple)
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
            FilterFooterView(unreadOnly: $articleStore.unreadOnly, summaryOnly: $articleStore.summaryOnly)
        }
        .onChange(of: articleStore.unreadOnly) { _, newVal in
            Task { await articleStore.fetchArticles(feedId: feedId, groupId: groupId, unreadOnly: newVal, includeSecret: groupStore.showSecretGroups) }
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
}
