import Foundation

// Thin layer holding UI state for ArticleListView.
// API calls go through ArticleStore (EnvironmentObject) directly in the view.
@MainActor
final class ArticleListViewModel: ObservableObject {
    @Published var unreadOnly = false

    func toggleUnreadFilter() {
        unreadOnly.toggle()
    }
}
