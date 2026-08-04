package com.mtkg.gogai.share

/// ACTION_SEND(text/plain) の EXTRA_TEXT から最初の http(s) URL を抽出する
/// （iOS ShareViewController.extractSharedURL 相当。iOS は UTType.url の添付を使うが、
/// Android の共有シートは text/plain のみのため正規表現で抽出する）。
private val urlRegex = Regex("""https?://\S+""")

fun extractSharedUrl(text: String?): String? {
    if (text.isNullOrBlank()) return null
    return urlRegex.find(text)?.value
}

/// EXTRA_SUBJECT が無い場合のフォールバック: EXTRA_TEXT から URL 以外の部分をタイトル候補として使う。
fun extractTitleFromSharedText(text: String, url: String): String? {
    val remainder = text.replace(url, "").trim()
    return remainder.ifBlank { null }
}

private val titleTagRegex = Regex("<title[^>]*>([\\s\\S]*?)</title>", RegexOption.IGNORE_CASE)

private val htmlEntities = listOf(
    "&amp;" to "&",
    "&lt;" to "<",
    "&gt;" to ">",
    "&quot;" to "\"",
    "&#39;" to "'",
    "&apos;" to "'",
    "&nbsp;" to " ",
)

/// HTML から <title> の中身を抽出し、最小限のエンティティデコードを行う
/// （iOS ShareViewController.extractTitleTag/decodeHTMLEntities 相当）。
fun extractTitleTag(html: String): String? {
    val match = titleTagRegex.find(html) ?: return null
    var inner = match.groupValues[1]
    for ((entity, replacement) in htmlEntities) {
        inner = inner.replace(entity, replacement)
    }
    val trimmed = inner.trim()
    return trimmed.ifBlank { null }
}
