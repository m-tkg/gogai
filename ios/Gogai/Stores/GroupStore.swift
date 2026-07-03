import Foundation

final class GroupStore: ObservableObject {
    @Published var groups: [Group] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    /// シークレットグループの表示フラグ（保存されない、バックグラウンド復帰でリセット）
    @Published var showSecretGroups = false
    /// 折りたたまれているグループIDのセット（未含有 = 展開済み）
    @Published private var collapsedGroupIds: Set<Int> = []

    private let cache: AppCache
    private var client: (any APIClientProtocol)?

    init(cache: AppCache = .shared) {
        self.cache = cache
        // 起動時にキャッシュからグループ一覧を読み込む
        self.groups = cache.loadGroups()
    }

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    var visibleGroups: [Group] {
        showSecretGroups ? groups : groups.filter { !$0.isSecret }
    }

    /// 非表示にすべきシークレットグループ所属フィードの ID 集合。
    /// シークレット表示中（showSecretGroups=true）は隠すものがないため空集合。
    func secretFeedIds(in feeds: [Feed]) -> Set<Int> {
        guard !showSecretGroups else { return [] }
        let secretGroupIds = Set(groups.filter { $0.isSecret }.map { $0.id })
        guard !secretGroupIds.isEmpty else { return [] }
        return Set(feeds.compactMap { feed in
            guard let gid = feed.group_id, secretGroupIds.contains(gid) else { return nil }
            return feed.id
        })
    }

    @MainActor
    func isExpanded(id: Int) -> Bool {
        !collapsedGroupIds.contains(id)
    }

    @MainActor
    func toggleExpanded(id: Int) {
        if collapsedGroupIds.contains(id) {
            collapsedGroupIds.remove(id)
        } else {
            collapsedGroupIds.insert(id)
        }
    }

    @MainActor
    func fetchGroups() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await GroupRepository(client: client).fetchAll()
            cache.saveGroups(groups)
        } catch {
            self.error = error
        }
    }

    @MainActor
    func createGroup(name: String) async throws {
        guard let client else { return }
        let newGroup = try await GroupRepository(client: client).create(name: name)
        groups.append(newGroup)
    }

    @MainActor
    func updateGroup(id: Int, name: String, isSecret: Int? = nil) async throws {
        guard let client else { return }
        let updated = try await GroupRepository(client: client).update(id: id, name: name, isSecret: isSecret)
        if let idx = groups.firstIndex(where: { $0.id == id }) {
            groups[idx] = updated
        }
    }

    @MainActor
    func deleteGroup(id: Int) async throws {
        guard let client else { return }
        try await GroupRepository(client: client).delete(id: id)
        groups.removeAll { $0.id == id }
        collapsedGroupIds.remove(id)
    }

    @MainActor
    func refreshGroup(id: Int) async throws -> RefreshResult {
        guard let client else { throw APIError.invalidURL }
        return try await GroupRepository(client: client).refresh(id: id)
    }

    @MainActor
    func reorderGroups(from source: IndexSet, to destination: Int) async throws {
        guard let client else { return }
        groups.move(fromOffsets: source, toOffset: destination)
        let ids = groups.map { $0.id }
        try await GroupRepository(client: client).reorder(ids: ids)
    }
}
