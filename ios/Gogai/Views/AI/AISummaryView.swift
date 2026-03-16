import SwiftUI

struct AISummaryView: View {
    let article: Article
    let action: ArticleRepository.AIAction

    @EnvironmentObject private var articleStore: ArticleStore
    @Environment(\.dismiss) private var dismiss

    @State private var output: String?
    @State private var isRunning = false
    @State private var error: Error?

    var title: String {
        switch action {
        case .summarize: return "AI要約"
        case .translate: return "AI翻訳"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(article.title ?? "（タイトルなし）")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Divider()

                    if isRunning {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("AIが処理中...")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.top, 40)
                    } else if let output {
                        Text(output)
                            .font(.body)
                            .lineSpacing(6)

                        Divider()

                        Button {
                            Task { await run(force: true) }
                        } label: {
                            Label("再実行（キャッシュ無視）", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    } else if let error {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)
                            Text(error.localizedDescription)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("再試行") {
                                Task { await run() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await run() }
        }
    }

    private func run(force: Bool = false) async {
        isRunning = true
        error = nil
        defer { isRunning = false }
        do {
            let result = try await articleStore.runAI(id: article.id, action: action, force: force)
            output = result.output
        } catch let err {
            self.error = err
        }
    }
}
