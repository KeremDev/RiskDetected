package com.riskdetectedan.core.data.support

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors SupportService.swift's send() — same edge function ("support-contact"), same body
 * shape. Attachments not ported (base64 file payloads — no file-picker UI built yet, deferred
 * with capture/upload's other simplifications). `userMessageLanguage` is hardcoded "tr" instead
 * of iOS's on-device NLLanguageRecognizer detection — Android is Turkish-only right now (see
 * every other Turkish-only note this session), so the detector would only ever report "tr"
 * anyway; not worth adding an ML Kit dependency for a value that's currently always the same.
 */
@Serializable
private data class SupportRequestBody(
    val subject: String,
    val message: String,
    val attachments: List<String> = emptyList(),
    @SerialName("app_language") val appLanguage: String = "tr",
    @SerialName("content_locale") val contentLocale: String = "tr-TR",
    @SerialName("user_message_language") val userMessageLanguage: String = "tr",
    @SerialName("preferred_response_language") val preferredResponseLanguage: String = "tr",
)

@Serializable
data class SupportRequestResult(
    val ok: Boolean? = null,
    @SerialName("support_id") val supportId: String? = null,
    @SerialName("delivery_status") val deliveryStatus: String? = null,
    val acknowledgement: String? = null,
)

@Singleton
class SupportRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun send(subject: String, message: String): RdResult<SupportRequestResult> = try {
        val result = client.functions.invoke(
            "support-contact",
            body = SupportRequestBody(subject = subject, message = message),
        ).body<SupportRequestResult>()
        RdResult.Success(result)
    } catch (t: Throwable) {
        RdResult.Failure("support_send_failed", t.message ?: "Destek talebi gönderilemedi.", t)
    }
}
