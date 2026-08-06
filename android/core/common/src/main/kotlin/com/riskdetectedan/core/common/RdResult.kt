package com.riskdetectedan.core.common

/**
 * Common outcome wrapper for repository/use-case boundaries.
 *
 * Mirrors the iOS app's [AppErrorMessage] pattern (App/Services/AppErrorMessage.swift):
 * backend is the single authority, the client only ever surfaces what the server said —
 * never invents its own capability/entitlement decisions. [Failure.code] should map 1:1 to
 * the shared error contract defined under `contracts/mobile/api/` (master plan §10.4).
 */
sealed interface RdResult<out T> {
    data class Success<T>(val value: T) : RdResult<T>
    data class Failure(
        val code: String,
        val message: String,
        val cause: Throwable? = null,
    ) : RdResult<Nothing>
}

inline fun <T, R> RdResult<T>.map(transform: (T) -> R): RdResult<R> = when (this) {
    is RdResult.Success -> RdResult.Success(transform(value))
    is RdResult.Failure -> this
}

inline fun <T> RdResult<T>.onSuccess(action: (T) -> Unit): RdResult<T> {
    if (this is RdResult.Success) action(value)
    return this
}

inline fun <T> RdResult<T>.onFailure(action: (RdResult.Failure) -> Unit): RdResult<T> {
    if (this is RdResult.Failure) action(this)
    return this
}
