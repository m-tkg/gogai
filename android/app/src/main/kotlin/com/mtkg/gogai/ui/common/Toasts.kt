package com.mtkg.gogai.ui.common

import android.content.Context
import android.widget.Toast

/// 未実装機能タップ時の共通プレースホルダ通知（Phase 5/6 まではこれで代替する）。
fun showNotYetAvailable(context: Context, message: String = "この機能は準備中です") {
    Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
}
