import SwiftUI

struct ArticleListView: View {
    let feedId: Int?
    let groupId: Int?
    @Binding var selectedArticle: Article?

    @EnvironmentObject private var articleStore: ArticleStore
    @State private var unreadOnly = false

    var body: some View {
        List(selection: $selectedArticle) {
            ForEach(articleStore.articles) { article in
                ArticleRowView(article: article)
                    .tag(article)
                    .onTapGesture {
                        selectedArticle = article
                        if !article.isRead {
                            Task { await articleStore.markAsRead(id: article.id) }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(listTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    unreadOnly.toggle()
                    Task { await articleStore.fetchArticles(feedId: feedId, groupId: groupId, unreadOnly: unreadOnly) }
                } label: {
                    Image(systemName: unreadOnly
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .overlay {
            if articleStore.isLoading {
                ProgressView()
            } else if articleStore.articles.isEmpty {
                ContentUnavailableView("記事がありません", systemImage: "newspaper")
            }
        }
        .refreshable {
            await articleStore.fetchArticles(feedId: feedId, groupId: groupId, unreadOnly: unreadOnly)
        }
        .task {
            await articleStore.fetchArticles(feedId: feedId, groupId: groupId)
        }
        .onChange(of: feedId) { _, newId in
            Task { await articleStore.fetchArticles(feedId: newId, groupId: groupId, unreadOnly: unreadOnly) }
        }
        .onChange(of: groupId) { _, newId in
            Task { await articleStore.fetchArticles(feedId: feedId, groupId: newId, unreadOnly: unreadOnly) }
        }
    }

    private var listTitle: String {
        if feedId == nil && groupId == nil { return "すべての記事" }
        return "記事"
    }
}
