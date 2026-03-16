import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore

    @Binding var selectedFeedId: Int?
    @Binding var selectedGroupId: Int?

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
                } label: {
                    Label("すべての記事", systemImage: "newspaper")
                }
                .tag("all")
            }

            ForEach(groupStore.groups) { group in
                Section {
                    ForEach(feedStore.feeds(for: group.id)) { feed in
                        FeedRowView(feed: feed, selectedFeedId: $selectedFeedId)
                    }
                } header: {
                    GroupRowView(group: group, selectedGroupId: $selectedGroupId)
                }
            }

            let ungroupedFeeds = feedStore.feeds.filter { $0.group_id == nil }
            if !ungroupedFeeds.isEmpty {
                Section("未分類") {
                    ForEach(ungroupedFeeds) { feed in
                        FeedRowView(feed: feed, selectedFeedId: $selectedFeedId)
                    }
                }
            }
        }
        .navigationTitle("gogai")
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
                    Image(systemName: "gear")
                }
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
