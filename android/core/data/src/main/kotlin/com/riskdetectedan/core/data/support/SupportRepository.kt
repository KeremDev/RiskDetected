package com.riskdetectedan.core.data.support

import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.common.RdClientMetadata
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors SupportService.swift's send() — same edge function ("support-contact"), same body
 * shape. In the absence of an on-device language recognizer, message and response language use
 * the active app language so English support requests are never routed as Turkish.
 */
@Serializable
private data class SupportRequestBody(
    val subject: String,
    val message: String,
    val attachments: List<SupportAttachmentPayload> = emptyList(),
    @SerialName("app_language") val appLanguage: String = RdClientMetadata.APP_LANGUAGE,
    @SerialName("content_locale") val contentLocale: String = RdClientMetadata.CONTENT_LOCALE,
    @SerialName("user_message_language") val userMessageLanguage: String = RdClientMetadata.APP_LANGUAGE,
    @SerialName("preferred_response_language") val preferredResponseLanguage: String = RdClientMetadata.APP_LANGUAGE,
)

/**
 * Real port of `SupportAttachmentPayload`/`SupportAttachmentDraft.payload` — closes the
 * "Attachments not ported" gap documented since feature #10. Same wire shape the real
 * `support-contact` edge function validates against (checked directly in
 * `supabase/functions/support-contact/index.ts`): base64-inlined `data`, max 3 attachments
 * (`MAX_ATTACHMENT_COUNT`), 5MB per file (`MAX_ATTACHMENT_BYTES`), 15MB total
 * (`MAX_ATTACHMENT_TOTAL_BYTES`) — [com.riskdetectedan.feature.profile.SupportViewModel]
 * enforces the same limits client-side before ever building this payload, same fail-fast
 * discipline as every other client-side-validated-to-match-server-limits field in this app
 * (finding measures cap, etc.).
 */
@Serializable
data class SupportAttachmentPayload(
    val filename: String,
    @SerialName("mime_type") val mimeType: String,
    val data: String,
    @SerialName("size_bytes") val sizeBytes: Int,
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
    suspend fun send(
        subject: String,
        message: String,
        attachments: List<SupportAttachmentPayload> = emptyList(),
    ): RdResult<SupportRequestResult> = try {
        val result = client.functions.invoke(
            "support-contact",
            body = SupportRequestBody(subject = subject, message = message, attachments = attachments),
        ).body<SupportRequestResult>()
        RdResult.Success(result)
    } catch (t: Throwable) {
        RdResult.Failure("support_send_failed", t.message ?: "Destek talebi gönderilemedi.", t)
    }
}
