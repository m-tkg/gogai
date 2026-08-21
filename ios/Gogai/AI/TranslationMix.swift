import Foundation

/// 文単位ミックス翻訳の「訳文で表示する文の割合」を扱う。
/// 文の通し番号に対して割合どおりに均等に訳文を散らし(Bresenham 的な整数演算)、
/// offset をずらすことで「混ぜ直し」を表現する。Android の `TranslationMix.kt` と同一ロジック。
enum TranslationMix {
    static let minRatio = 0
    static let maxRatio = 100
    static let step = 10
    /// 初期値。参考: 参照実装(Mazelingo)の既定値 40%
    static let defaultRatio = 40

    /// 通し番号 index の文を訳文で表示するかどうか(ratio は 0〜100 のパーセント)
    static func isTranslated(index: Int, ratio: Int, offset: Int = 0) -> Bool {
        let r = clamp(ratio)
        let j = index + offset
        return ((j + 1) * r) / 100 > (j * r) / 100
    }

    static func clamp(_ ratio: Int) -> Int {
        min(max(ratio, minRatio), maxRatio)
    }

    /// UserDefaults に保存した割合(未設定なら defaultRatio)
    static var savedRatio: Int {
        get {
            guard UserDefaults.standard.object(forKey: DefaultsKeys.translationMixRatio) != nil else { return defaultRatio }
            return clamp(UserDefaults.standard.integer(forKey: DefaultsKeys.translationMixRatio))
        }
        set {
            UserDefaults.standard.set(clamp(newValue), forKey: DefaultsKeys.translationMixRatio)
        }
    }
}
