package com.mtkg.gogai.ai

/**
 * AI へのテキスト生成依頼を抽象化するインターフェース。
 * iOS の TextGenerating プロトコル（AI/LocalArticleAI.swift）に対応する。
 * Android はリモート AI（OpenAI/Gemini/Claude）のみをサポートするため、
 * 実装は [RemoteAITextGenerator] のみだが、テストではフェイク実装に差し替えられる。
 */
fun interface TextGenerating {
    suspend fun generate(instructions: String, prompt: String): String
}
