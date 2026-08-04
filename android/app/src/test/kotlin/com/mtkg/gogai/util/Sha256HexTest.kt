package com.mtkg.gogai.util

import org.junit.Assert.assertEquals
import org.junit.Test

class Sha256HexTest {
    @Test
    fun `既知のベクトルに対して正しいダイジェストを返す`() {
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "abc".sha256HexDigest(),
        )
    }

    @Test
    fun `空文字列のダイジェストを返す`() {
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "".sha256HexDigest(),
        )
    }
}
