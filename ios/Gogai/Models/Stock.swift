import Foundation

struct Stock: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let url: String
    let title: String?
    let source: String
    let category_id: Int
    let category_name: String
    let summary: String?
    let has_translation: Bool
    let stocked_at: String
    let created_at: String

    /// 指定フィールドだけ差し替えた新しい Stock を返す
    func updating(title: String? = nil, categoryId: Int? = nil, categoryName: String? = nil, summary: String?? = nil, hasTranslation: Bool? = nil) -> Stock {
        Stock(id: id, url: url,
              title: title ?? self.title,
              source: source,
              category_id: categoryId ?? category_id,
              category_name: categoryName ?? category_name,
              summary: summary ?? self.summary,
              has_translation: hasTranslation ?? has_translation,
              stocked_at: stocked_at,
              created_at: created_at)
    }
}

struct StockCategory: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let display_order: Int
    let created_at: String
    let stock_count: Int
}

struct StockTranslationPayload: Codable, Sendable {
    let segments: String
    let translated_at: String
}
