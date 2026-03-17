import SwiftUI

struct ArticleListView: View {
    let feedId: Int?
    let groupId: Int?
    @Binding var selectedArticle: Article?
    var onArticleSelected: ((Article) -> Void)?

    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var feedStore: FeedStore

    @State private var showMarkAllConfirm = false

    private var displayedArticles: [Article] {
        articleStore.summaryOnly
            ? articleStore.articles.filter { $0.ai_summary != nil }
            : articleStore.articles
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task { await articleStore.summarize(id: article.id) }
                        } label: {
                            Label("AI要約", systemImage: "sparkles")
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
                Button {
                    showMarkAllConfirm = true
                } label: {
                    Image(systemName: "envelope.open")
                }
                .disabled(displayedArticles.allSatisfy { $0.isRead })
            }
        }
        .confirmationDialog("表示中の記事をすべて既読にしますか？", isPresented: $showMarkAllConfirm, titleVisibility: .visible) {
            Button("すべて既読にする", role: .destructive) {
                Task { await articleStore.markAllAsRead() }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            FilterFooterView(unreadOnly: $articleStore.unreadOnly, summaryOnly: $articleStore.summaryOnly)
        }
        .onChange(of: articleStore.unreadOnly) { _, newVal in
            Task { await articleStore.fetchArticles(feedId: feedId, groupId: groupId, unreadOnly: newVal) }
        }
        .overlay {
            if articleStore.isLoading {
                ProgressView()
            } else if displayedArticles.isEmpty {
                ContentUnavailableView("記事がありません", systemImage: "newspaper")
            }
        }
        .refreshable {
            try? await feedStore.refreshAll()
        }
        .task {
            await articleStore.fetchArticles(feedId: feedId, groupId: groupId)
        }
        .onChange(of: feedId) { _, newId in
            Task { await articleStore.fetchArticles(feedId: newId, groupId: groupId) }
        }
        .onChange(of: groupId) { _, newId in
            Task { await articleStore.fetchArticles(feedId: feedId, groupId: newId) }
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
