import SwiftUI

/// ストック機能のルートビュー。カテゴリ一覧から StockListView/StockDetailView への
/// 遷移(.stockDestinations())までを完結して持ち、記事閲覧側(RootView/
/// ArticleNavigationRootView)は Stock 関連ビューの内部を一切知らずに済む。
///
/// iPad では独立した fullScreenCover のルートとして(自身の NavigationStack で包む)、
/// iPhone では共有 NavigationStack への push destination として(NavigationStack は
/// 呼び出し側が既に持っているため、こちらでは包まない)使う。
struct StockRootView: View {
    /// true の場合、閉じるボタンを表示する(iPad の fullScreenCover 表示用)
    var isModal: Bool = false

    var body: some View {
        StockCategoryListView(isModal: isModal)
            .stockDestinations()
    }
}
