package com.mtkg.gogai.cache

/// SharedPreferences のキーを一元管理する（散在ハードコードと衝突を防ぐ、iOS DefaultsKeys の移植）
object DefaultsKeys {
    const val UNREAD_ONLY = "unreadOnly"
    const val SORT_ORDER = "sortOrder"
    const val SERVER_URL = "serverURL"
    const val RESOLVED_SERVER_URL = "resolvedServerURL"
    const val AI_PROVIDER = "aiProvider"
    const val STOCK_SORT_ASCENDING = "stockSortAscending"
    const val STOCK_SUMMARY_QUEUE = "stockSummaryQueue"
    const val STOCK_SUMMARY_ERRORS = "stockSummaryErrors"
}
