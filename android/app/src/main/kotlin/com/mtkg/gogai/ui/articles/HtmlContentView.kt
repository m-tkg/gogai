package com.mtkg.gogai.ui.articles

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.webkit.WebView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

/// 記事本文の HTML を表示する WebView（iOS HTMLContentView の移植）。
/// iOS 版は WKWebView の高さを JS で測定して ScrollView に埋め込んでいるが、Android 版は
/// WebView 自体にスクロールを担当させることで高さ測定・JS コールバックの必要をなくしている。
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun HtmlContentView(html: String, modifier: Modifier = Modifier) {
    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { context ->
            WebView(context).apply {
                setBackgroundColor(AndroidColor.TRANSPARENT)
                settings.javaScriptEnabled = false
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
            }
        },
        update = { webView ->
            webView.loadDataWithBaseURL(null, styledHtml(html), "text/html", "UTF-8", null)
        },
    )
}

/// iOS HTMLContentView.swift の CSS をそのまま移植（ダークモード対応の prefers-color-scheme を含む）
private fun styledHtml(bodyHtml: String): String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      body {
        font-family: sans-serif;
        font-size: 17px;
        line-height: 1.7;
        margin: 0; padding: 16px;
        color: #000;
        word-break: break-word;
      }
      @media (prefers-color-scheme: dark) {
        body { color: #eee; }
        a { color: #4af; }
      }
      img { max-width: 100%; height: auto; border-radius: 6px; }
      pre, code { font-size: 14px; overflow-x: auto; }
      a { color: #007aff; }
      p { margin: 0 0 1em; }
    </style>
    </head>
    <body>$bodyHtml</body>
    </html>
""".trimIndent()
