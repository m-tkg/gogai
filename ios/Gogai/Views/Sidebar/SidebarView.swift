import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore
    @Environment(\.scenePhase) private var scenePhase

    @Binding var selectedFeedId: Int?
    @Binding var selectedGroupId: Int?
    var onNavigate: ((ArticleDestination) -> Void)?

    @State private var showAddFeed = false
    @State private var showAddGroup = false
    @State private var showSettings = false
    @State private var isRefreshing = false
    @State private var refreshError: Error?

    var body: some View {
        List(selection: Binding(
            get: { selectedFeedId.map { "feed-\($0)" } ?? selectedGroupId.map { "group-\($0)" } ?? "all" },
            set: { _ in }
        )) {
            Section("フィード") {
                Button {
                    selectedFeedId = nil
                    selectedGroupId = nil
                    onNavigate?(ArticleDestination(feedId: nil, groupId: nil))
                } label: {
                    Label("すべての記事", systemImage: "newspaper")
                }
                .tag("all")
            }

            ForEach(groupStore.visibleGroups) { group in
                let feeds = feedStore.feeds(for: group.id).filter { feed in
                    !articleStore.unreadOnly || articleStore.unreadCount(for: feed.id) > 0
                }
                if !feeds.isEmpty {
                    Section {
                        ForEach(feeds) { feed in
                            FeedRowView(feed: feed, selectedFeedId: $selectedFeedId, onNavigate: onNavigate)
                        }
                    } header: {
                        GroupRowView(group: group, selectedGroupId: $selectedGroupId, onNavigate: onNavigate)
                    }
                }
            }

            let ungroupedFeeds = feedStore.feeds.filter { $0.group_id == nil }.filter { feed in
                !articleStore.unreadOnly || articleStore.unreadCount(for: feed.id) > 0
            }
            if !ungroupedFeeds.isEmpty {
                Section("未分類") {
                    ForEach(ungroupedFeeds) { feed in
                        FeedRowView(feed: feed, selectedFeedId: $selectedFeedId, onNavigate: onNavigate)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FilterFooterView(unreadOnly: $articleStore.unreadOnly, summaryOnly: $articleStore.summaryOnly)
        }
        .navigationTitle("Feed list")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await refreshAll() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)

                Menu {
                    Button {
                        showAddFeed = true
                    } label: {
                        Label("フィードを追加", systemImage: "plus.circle")
                    }
                    Button {
                        showAddGroup = true
                    } label: {
                        Label("グループを追加", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: groupStore.showSecretGroups ? "gear.badge" : "gear")
                        .foregroundStyle(groupStore.showSecretGroups ? .orange : .primary)
                }
                .simultaneousGesture(
                    LongPressGesture().onEnded { _ in
                        groupStore.showSecretGroups.toggle()
                    }
                )
                .accessibilityLabel(groupStore.showSecretGroups ? "設定（シークレット表示中）" : "設定")
                .accessibilityHint("長押しでシークレットグループの表示を切り替え")
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // バックグラウンドから復帰した時のみリセット（初回起動時は除く）
            if newPhase == .active && oldPhase == .background {
                groupStore.showSecretGroups = false
            }
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedView()
        }
        .sheet(isPresented: $showAddGroup) {
            AddGroupView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("エラー", isPresented: Binding(
            get: { refreshError != nil },
            set: { if !$0 { refreshError = nil } }
        )) {
            Button("OK") { refreshError = nil }
        } message: {
            Text(refreshError?.localizedDescription ?? "")
        }
    }

    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            _ = try await feedStore.refreshAll()
        } catch {
            refreshError = error
        }
    }
}
