import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.scenePhase) private var scenePhase

    @Binding var selectedFeedId: Int?
    @Binding var selectedGroupId: Int?
    var onNavigate: ((ArticleDestination) -> Void)?

    @State private var showAddFeed = false
    @State private var showAddGroup = false
    @State private var showSettings = false
    @State private var refreshError: Error?
    @State private var reorderError: Error?
    @State private var rotationAngle: Double = 0
    @State private var isEditing = false

    private var totalBadgeCount: Int {
        articleStore.badgeCount(excludingFeedIds: groupStore.secretFeedIds(in: feedStore.feeds))
    }

    private var listSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedFeedId.map { "feed-\($0)" } ?? selectedGroupId.map { "group-\($0)" } ?? "all" },
            set: { _ in }
        )
    }

    private var refreshErrorBinding: Binding<Bool> {
        Binding(
            get: { refreshError != nil },
            set: { if !$0 { refreshError = nil } }
        )
    }

    private var reorderErrorBinding: Binding<Bool> {
        Binding(
            get: { reorderError != nil },
            set: { if !$0 { reorderError = nil } }
        )
    }

    private var isNetworkActive: Bool {
        articleStore.isLoading
            || feedStore.isLoading
            || feedStore.isRefreshing
            || groupStore.isLoading
            || settingsStore.isLoading
    }

    private var visibleUngroupedFeeds: [Feed] {
        feedStore.feeds.filter { $0.group_id == nil }.filter { feed in
            articleStore.hasVisibleArticle(for: feed.id)
        }
    }

    @ViewBuilder
    private func groupSection(for group: Group) -> some View {
        let feeds = feedStore.feeds(for: group.id).filter { feed in
            articleStore.hasVisibleArticle(for: feed.id)
        }
        if !feeds.isEmpty {
            Section {
                if groupStore.isExpanded(id: group.id) {
                    ForEach(feeds) { feed in
                        FeedRowView(feed: feed, selectedFeedId: $selectedFeedId, onNavigate: onNavigate)
                    }
                    .onMove { from, to in
                        Task { try? await feedStore.reorderFeeds(from: from, to: to, groupId: group.id) }
                    }
                }
            } header: {
                GroupRowView(group: group, selectedGroupId: $selectedGroupId, onNavigate: onNavigate)
            }
        }
    }

    var body: some View {
        List(selection: listSelectionBinding) {
            Section("フィード") {
                Button {
                    selectedFeedId = nil
                    selectedGroupId = nil
                    onNavigate?(ArticleDestination(feedId: nil, groupId: nil))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "newspaper")
                            .foregroundStyle(.secondary)
                        Text("すべての記事")
                            .foregroundStyle(.primary)
                        UnreadCountBadge(count: totalBadgeCount)
                    }
                }
                .tag("all")
            }

            ForEach(groupStore.visibleGroups) { group in
                groupSection(for: group)
            }
            .onMove { from, to in
                Task {
                    do {
                        try await groupStore.reorderGroups(from: from, to: to)
                    } catch {
                        reorderError = error
                    }
                }
            }

            if !visibleUngroupedFeeds.isEmpty {
                Section("未分類") {
                    ForEach(visibleUngroupedFeeds) { feed in
                        FeedRowView(feed: feed, selectedFeedId: $selectedFeedId, onNavigate: onNavigate)
                    }
                    .onMove { from, to in
                        Task { try? await feedStore.reorderFeeds(from: from, to: to, groupId: nil) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FilterFooterView(unreadOnly: $articleStore.unreadOnly, favoriteOnly: $articleStore.favoriteOnly)
        }
        .navigationTitle("Feed list")
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isEditing.toggle()
                } label: {
                    Text(isEditing ? "完了" : "編集")
                        .font(.subheadline)
                }

                Button {
                    Task { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(rotationAngle))
                }
                .disabled(feedStore.isRefreshing)
                .onChange(of: feedStore.isRefreshing) { _, isRefreshing in
                    if isRefreshing {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    } else {
                        withAnimation(.default) {
                            rotationAngle = 0
                        }
                    }
                }

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

            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: groupStore.showSecretGroups ? "gear.badge" : "gear")
                        .foregroundStyle(groupStore.showSecretGroups ? .orange : .primary)
                }
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        groupStore.showSecretGroups.toggle()
                    }
                )
                .accessibilityLabel(groupStore.showSecretGroups ? "設定（シークレット表示中）" : "設定")
                .accessibilityHint("長押しでシークレットグループの表示を切り替え")

                if isNetworkActive {
                    ProgressView()
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // バックグラウンド移行時にシークレットモードをオフ
            if newPhase == .background {
                groupStore.showSecretGroups = false
            }
        }
        .onChange(of: groupStore.showSecretGroups) { _, newVal in
            // シークレットモードON時にバッジ用のサーバー集計を最新化する
            // （counts は常にシークレット込みなので取得し直すだけでよい）
            if newVal {
                Task { await articleStore.refreshCounts() }
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
        .alert("エラー", isPresented: refreshErrorBinding) {
            Button("OK") { refreshError = nil }
        } message: {
            Text(refreshError?.localizedDescription ?? "")
        }
        .alert("並び替えエラー", isPresented: reorderErrorBinding) {
            Button("OK") { reorderError = nil }
        } message: {
            Text(reorderError?.localizedDescription ?? "")
        }
    }

    private func refreshAll() async {
        do {
            _ = try await feedStore.refreshAll()
            // 未読件数バッジ更新のためフィード一覧を再取得
            await feedStore.fetchFeeds()
        } catch {
            refreshError = error
        }
    }
}
