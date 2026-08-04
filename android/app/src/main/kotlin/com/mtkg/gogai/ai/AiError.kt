package com.mtkg.gogai.ai

/**
 * AI 関連の処理で共通して発生するエラー（iOS の LocalAIError, AI/LocalAIError.swift の移植）。
 *
 * [AiUnavailable] のメッセージのみ iOS 原文（オンデバイス Foundation Models 前提の文言）から
 * 意図的に変更している。Android はオンデバイス AI を持たずリモート AI のみのため、
 * 「iOS 27 以上と Apple Intelligence の有効化が必要」という原文はそのまま移植できない。
 * それ以外の3件は原文どおりのメッセージ。
 */
sealed class AiError(message: String) : Exception(message) {
    /** タイトル・本文のどちらも空で AI に渡すテキストがない */
    object EmptyContent : AiError("本文が空のため処理できません")

    /** モデル応答から期待した形式の結果を取り出せなかった(例: 翻訳の id タグ) */
    object ParseFailed : AiError("AI の応答を解析できませんでした")

    /** AI を利用できない(API キー未設定など) */
    object AiUnavailable : AiError("AI を利用できません。設定画面で API キーを入力してください。")

    /** URL が不正で処理できない */
    object InvalidUrl : AiError("URL が不正です")
}
