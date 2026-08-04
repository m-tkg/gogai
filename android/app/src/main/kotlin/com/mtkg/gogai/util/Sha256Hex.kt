package com.mtkg.gogai.util

import java.security.MessageDigest

/**
 * UTF-8 バイト列の SHA-256 hex ダイジェスト（小文字）。
 * iOS の String.sha256HexDigest（Utilities/SHA256HexDigest.swift）と同じ計算。
 */
fun String.sha256HexDigest(): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { "%02x".format(it) }
}
