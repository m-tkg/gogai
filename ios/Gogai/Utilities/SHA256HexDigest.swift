import CryptoKit
import Foundation

extension String {
    /// UTF-8 バイト列の SHA256 hex ダイジェスト。
    /// TranslationCache(ローカル TTL キャッシュのキー)と FMTranslatedPageView
    /// (サーバー同期用の原文バージョニング)が同じ計算を重複実装していたため、
    /// ここに一本化する。ただしこの2つの用途自体(キャッシュ vs 変更検知)は目的が
    /// 異なるため、ダイジェスト計算以外のロジックは統合しない。
    var sha256HexDigest: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
