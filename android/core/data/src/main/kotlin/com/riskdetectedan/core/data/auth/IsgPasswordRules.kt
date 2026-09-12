package com.riskdetectedan.core.data.auth

/** New-password UX validation; do NOT apply it to existing-password sign-in.
 * GoTrue 2.195.0's minimum is bytes. Server Unicode minimum remains a rollout gate. */
data class IsgPasswordRules(
    val minimumCharacters: Boolean,
    val uppercase: Boolean,
    val lowercase: Boolean,
    val digit: Boolean,
    val maximumBytes: Boolean,
) {
    val valid: Boolean get() = minimumCharacters && uppercase && lowercase && digit && maximumBytes
    companion object {
        fun evaluate(password: String) = IsgPasswordRules(
            password.codePointCount(0, password.length) >= 8,
            password.any { it in 'A'..'Z' }, password.any { it in 'a'..'z' }, password.any { it in '0'..'9' },
            password.toByteArray(Charsets.UTF_8).size <= 72,
        )
    }
}
