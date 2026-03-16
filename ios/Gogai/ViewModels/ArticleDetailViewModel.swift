import Foundation

// Thin layer holding AI operation UI state for ArticleDetailView / AISummaryView.
// API calls go through ArticleStore (EnvironmentObject) directly in the view.
@MainActor
final class ArticleDetailViewModel: ObservableObject {
    @Published private(set) var aiOutput: String?
    @Published private(set) var isAIRunning = false
    @Published var aiError: Error?

    func beginRunning() {
        isAIRunning = true
        aiError = nil
    }

    func finishWithOutput(_ output: String) {
        aiOutput = output
        isAIRunning = false
    }

    func finishWithError(_ error: Error) {
        aiError = error
        isAIRunning = false
    }

    func clearOutput() {
        aiOutput = nil
        aiError = nil
    }
}
