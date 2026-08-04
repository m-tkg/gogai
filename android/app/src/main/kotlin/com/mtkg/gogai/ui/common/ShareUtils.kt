package com.mtkg.gogai.ui.common

import android.content.Context
import android.content.Intent

/// URL を Android の共有シート（ACTION_SEND）で共有する（iOS ShareSheet 相当）。
fun shareUrl(context: Context, url: String) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
    }
    context.startActivity(Intent.createChooser(sendIntent, null))
}
