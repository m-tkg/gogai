import SwiftUI
import SafariServices

struct ArticleDetailView: View {
    let article: Article

    @EnvironmentObject private var articleStore: ArticleStore

    @State private var showSafari = false
    @State private var showAISummary = false
    @State private var showAITranslation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(article.title ?? "（タイトルなし）")
                    .font(.title2)
                    .fontWeight(.bold)

                // Meta
                HStack {
                    if let published = article.published_at {
                        Label(published.displayDate, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
                        .font(.caption)
                    }
                }

                Divider()

                // Content
                if let content = article.content ?? article.summary {
                    Text(content)
                        .font(.body)
                        .lineSpacing(6)
                } else {
                    Text("本文がありません")
                        .foregroundStyle(.secondary)
                }

                Divider()

                // AI Actions
                HStack(spacing: 12) {
                    Button {
                        showAISummary = true
                    } label: {
                        Label("AI要約", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showAITranslation = true
                    } label: {
                        Label("AI翻訳", systemImage: "character.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("記事")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let link = article.link, URL(string: link) != nil {
                    Button {
                        showSafari = true
                    } label: {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .sheet(isPresented: $showSafari) {
            if let link = article.link, let url = URL(string: link) {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showAISummary) {
            AISummaryView(article: article, action: .summarize)
        }
        .sheet(isPresented: $showAITranslation) {
            AISummaryView(article: article, action: .translate)
        }
        .onAppear {
            if !article.isRead {
                Task { await articleStore.markAsRead(id: article.id) }
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
