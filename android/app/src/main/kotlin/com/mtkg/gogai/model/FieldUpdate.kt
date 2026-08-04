package com.mtkg.gogai.model

/// nil への更新と「変更しない」を型安全に区別するための汎用 sealed class（iOS FieldUpdate の移植）
sealed class FieldUpdate<out T> {
    data object Keep : FieldUpdate<Nothing>()
    data object Clear : FieldUpdate<Nothing>()
    data class Set<T>(val value: T) : FieldUpdate<T>()

    fun applyTo(current: @UnsafeVariance T?): T? = when (this) {
        is Keep -> current
        is Clear -> null
        is Set -> value
    }
}
