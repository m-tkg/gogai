import Foundation

/// nil への更新と「変更しない」を型安全に区別するための汎用 enum
enum FieldUpdate<T: Sendable>: Sendable {
    case keep
    case clear
    case set(T)

    func apply(to current: T?) -> T? {
        switch self {
        case .keep: return current
        case .clear: return nil
        case .set(let value): return value
        }
    }
}
