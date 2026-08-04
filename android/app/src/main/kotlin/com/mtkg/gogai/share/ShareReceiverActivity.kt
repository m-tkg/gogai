package com.mtkg.gogai.share

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.mtkg.gogai.GogaiApplication
import com.mtkg.gogai.di.AppContainer
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.ui.theme.GogaiTheme
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/// 共有シート(ACTION_SEND, text/plain)のエントリポイント。共有された URL を抽出して
/// ストック追加フォームを表示する（iOS GogaiShareExtension.ShareViewController の移植）。
/// iOS は App Extension（別プロセス・App Group 経由）だが、Android の共有ターゲットは
/// 通常のアプリと同一プロセスの Activity として実装できるため、AppContainer をそのまま使う。
class ShareReceiverActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val container = (application as GogaiApplication).container
        val sharedText = if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            intent.getStringExtra(Intent.EXTRA_TEXT)
        } else {
            null
        }
        val sharedUrl = extractSharedUrl(sharedText)

        if (sharedUrl == null) {
            finish()
            return
        }

        val subjectTitle = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()?.takeIf { it.isNotEmpty() }
        val textTitle = subjectTitle ?: sharedText?.let { extractTitleFromSharedText(it, sharedUrl) }

        setContent {
            GogaiTheme {
                ShareStockScreen(
                    url = sharedUrl,
                    initialTitleGuess = textTitle,
                    client = makeShareClient(container),
                    httpClient = container.httpClient,
                    onFinish = { finish() },
                )
            }
        }
    }
}

/// 共有 URL のストック登録に使う ApiClient を組み立てる。
/// resolvedUrl（Gist 解決済みトンネル URL 等）があればそれを使い、無ければ raw serverUrl
/// （Gist URL でない場合のみ）を使う。同一プロセスのため iOS のような App Group 経由の
/// 値受け渡しは不要で、AppContainer の ServerUrlManager をそのまま参照する
/// （iOS ShareStockView.makeClient 相当）。
private fun makeShareClient(container: AppContainer): ApiClient? {
    val resolved = container.serverUrlManager.resolvedUrl.value
    if (resolved != null) {
        return ApiClient(baseUrl = resolved, httpClient = container.httpClient)
    }
    val raw = container.serverUrlManager.serverUrl.value ?: return null
    val rawUrl = raw.toHttpUrlOrNull() ?: return null
    if (rawUrl.host == "gist.github.com") return null
    return ApiClient(baseUrl = rawUrl, httpClient = container.httpClient)
}
