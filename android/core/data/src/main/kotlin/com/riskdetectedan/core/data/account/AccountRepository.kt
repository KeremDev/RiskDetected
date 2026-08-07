package com.riskdetectedan.core.data.account

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Mirrors AnalysisService.swift's AccountDeletionRequestResult exactly, including the
 * shouldClearLocalSession derivation (completed || alreadyCompleted || authUserDeleted). */
@Serializable
data class AccountDeletionRequestResult(
    val ok: Boolean? = null,
    val completed: Boolean? = null,
    @SerialName("already_completed") val alreadyCompleted: Boolean? = null,
    @SerialName("auth_user_deleted") val authUserDeleted: Boolean? = null,
    @SerialName("request_id") val requestId: String? = null,
    @SerialName("support_id") val supportId: String? = null,
    val message: String? = null,
) {
    val shouldClearLocalSession: Boolean
        get() = completed == true || alreadyCompleted == true || authUserDeleted == true
}

@Serializable
private data class AccountDeletionRequestBody(
    val email: String?,
    @SerialName("request_id") val requestId: String,
    @SerialName("support_id") val supportId: String,
)

@Singleton
class AccountRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    /** Mirrors requestAccountDeletion() — same edge function
     * (request-account-deletion), same body shape, same "not done unless
     * shouldClearLocalSession" success criterion. Caller is responsible for signing out
     * locally afterward (this repository doesn't reach into AuthRepository itself — that's a
     * cross-cutting call the ViewModel should make explicit, not hide in a data-layer side effect). */
    suspend fun requestAccountDeletion(email: String?): RdResult<AccountDeletionRequestResult> = try {
        val requestId = UUID.randomUUID().toString()
        val supportId = UUID.randomUUID().toString()
        val result = client.functions.invoke(
            "request-account-deletion",
            body = AccountDeletionRequestBody(email, requestId, supportId),
        ).body<AccountDeletionRequestResult>()

        if (result.shouldClearLocalSession) {
            RdResult.Success(result)
        } else {
            RdResult.Failure(
                code = "account_deletion_incomplete",
                message = result.message ?: "Hesap silme işlemi tamamlanamadı.",
            )
        }
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "account_deletion_failed",
            message = t.message ?: "Hesap silme işlemi başlatılamadı.",
            cause = t,
        )
    }
}
