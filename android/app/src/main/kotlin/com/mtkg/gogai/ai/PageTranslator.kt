package com.mtkg.gogai.ai

import com.mtkg.gogai.util.sha256HexDigest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * サーバーに保存する翻訳セグメントの形式（iOS の FMTranslationPayload,
 * AI/FMTranslatedPageView.swift の移植）。segments は stocks.translation の
 * 不透明な JSON としてそのまま保存・取得される。
 */
@Serializable
data class TranslationPayload(val version: Int, val segments: List<Segment>) {
    @Serializable
    data class Segment(
        /** 文 index(文書順の通し番号) */
        val i: Int,
        /** 原文の SHA256(ページが変化していないかの照合に使う) */
        val h: String,
        /** 訳文 */
        val t: String,
    )

    companion object {
        /**
         * 現在の形式。version 1 はノード単位(index = テキストノード)だったが、
         * version 2 から文単位(index = 文の通し番号)になり互換性がないため、version 不一致は復元せず再翻訳する
         */
        const val CURRENT_VERSION = 2
    }
}

/**
 * FMTranslatedPageView（AI/FMTranslatedPageView.swift）のモデル部分(View を除く純ロジック)の移植。
 * 翻訳結果は文単位でサーバーに保存し、再表示時は原文ハッシュが一致する文だけ復元する
 * (ページが変化した箇所は原文のまま表示する)。
 * WebView からのテキスト抽出・DOM への書き戻し・サーバー保存 API 呼び出しは UI 層の責務であり、
 * このクラスは「保存済みペイロード + 現在の全文 → 復元/翻訳対象の仕分けと保存用ペイロードの生成」
 * という純粋なロジックだけを持つ。
 */
class PageTranslator(private val batchTranslator: PageBatchTranslator) {

    data class Result(
        /** 保存済みペイロードのうち原文ハッシュが一致し復元できたセグメント(index → 訳文) */
        val restored: Map<Int, String>,
        /** 今回新たに翻訳できたセグメント(index → 訳文) */
        val translatedNow: Map<Int, String>,
        /** restored と translatedNow をマージした、DOM に適用すべき全訳文 */
        val merged: Map<Int, String>,
        /** サーバーに保存すべき JSON(何も訳文がなければ null) */
        val payloadJson: String?,
    )

    /**
     * texts: ページの全文(文書順、文単位に分割済み)
     * savedPayloadJson: サーバー保存済みの翻訳 JSON(なければ、または強制再翻訳なら null)
     * pageTitle: 翻訳プロンプトに使うページタイトル
     * onProgress: 翻訳対象セグメントの完了数が変わるたびに (完了数, 総数) で呼ばれる（UI 進捗表示用、省略可）
     */
    suspend fun translate(
        texts: List<String>,
        savedPayloadJson: String?,
        pageTitle: String,
        onProgress: ((completed: Int, total: Int) -> Unit)? = null,
    ): Result {
        if (texts.isEmpty()) return Result(emptyMap(), emptyMap(), emptyMap(), null)

        val savedByIndex = decodeSegments(savedPayloadJson).orEmpty().associateBy { it.i }

        // 原文ハッシュが一致する文だけ復元し、それ以外(未保存・ページ変化)を翻訳対象にする
        val restored = mutableMapOf<Int, String>()
        val indicesToTranslate = mutableListOf<Int>()
        texts.forEachIndexed { index, text ->
            val segment = savedByIndex[index]
            if (segment != null && segment.h == hash(text)) {
                restored[index] = segment.t
            } else {
                indicesToTranslate.add(index)
            }
        }

        val translatedNow = if (indicesToTranslate.isEmpty()) {
            emptyMap()
        } else {
            batchTranslator.translate(texts, indicesToTranslate, pageTitle, onProgress)
        }

        val merged = restored + translatedNow
        val payloadJson = if (merged.isEmpty()) {
            null
        } else {
            val segments = merged.map { (index, text) ->
                TranslationPayload.Segment(i = index, h = hash(texts[index]), t = text)
            }
            Json.encodeToString(TranslationPayload.serializer(), TranslationPayload(version = TranslationPayload.CURRENT_VERSION, segments = segments))
        }

        return Result(restored = restored, translatedNow = translatedNow, merged = merged, payloadJson = payloadJson)
    }

    companion object {
        fun hash(text: String): String = text.sha256HexDigest()

        /** 保存済みペイロードを復号する。形式が異なる(旧ノード単位など)場合は null を返し、全文を翻訳し直す */
        fun decodeSegments(json: String?): List<TranslationPayload.Segment>? {
            if (json.isNullOrEmpty()) return null
            return runCatching {
                Json.decodeFromString(TranslationPayload.serializer(), json)
                    .takeIf { it.version == TranslationPayload.CURRENT_VERSION }
                    ?.segments
            }.getOrNull()
        }
    }
}
