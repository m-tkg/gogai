package com.mtkg.gogai.ui.common

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent

/// Custom Tabs で URL を開く。
/// iOS 版は記事ページを push 遷移の BrowserView（SFSafariViewController）で表示するが、
/// Android では同等の「アプリ内ブラウザ」体験として Chrome Custom Tabs を使う
/// （SFSafariViewController 相当の広告ブロック等の Safari 拡張は Android に対応物がないため対象外）。
fun openInCustomTabs(context: Context, url: String) {
    val intent = CustomTabsIntent.Builder().build()
    intent.launchUrl(context, Uri.parse(url))
}
