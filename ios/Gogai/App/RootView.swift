import SwiftUI

/// アプリのトップレベルビュー。実際のナビゲーション状態・プラットフォーム別レイアウトは
/// ArticleNavigationRootView(記事閲覧)が持つ。
///
/// 起動時のデータ取得は GogaiApp.configureStores() が唯一の起点であり、ここでは行わない
/// (以前は RootView.task でも groups/feeds/articles を独立にフェッチしており、
/// 通常のコールドスタートで2回リクエストが飛んでいた)。
struct RootView: View {
    var body: some View {
        ArticleNavigationRootView()
    }
}
