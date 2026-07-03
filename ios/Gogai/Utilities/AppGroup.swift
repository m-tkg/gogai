import Foundation

/// 本体アプリとシェア拡張でサーバー URL を共有するための App Group。
/// 拡張はネットワーク到達性や Gist 再解決を行わず、本体アプリが解決した
/// resolvedServerURL をそのまま読むだけなので、この suite への書き込みは
/// 本体アプリ側（ServerURLManager）のみが行う。
enum AppGroup {
    static let id = "group.com.mtkg.gogai"

    /// App Group が利用できない場合(未署名のビルドなど)は標準 UserDefaults にフォールバックする
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
