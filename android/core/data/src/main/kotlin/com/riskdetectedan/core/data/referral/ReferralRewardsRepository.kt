package com.riskdetectedan.core.data.referral

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import javax.inject.Inject
import javax.inject.Singleton

/** The invite programme as the server reports it (iOS `ReferralDashboard`). */
@Serializable
data class ReferralDashboard(
    val campaign: Campaign,
    @SerialName("referral_code") val referralCode: String,
    @SerialName("share_url") val shareUrl: String,
    @SerialName("share_message") val shareMessage: String,
    val counts: Counts,
    @SerialName("sent_invites") val sentInvites: List<Invite> = emptyList(),
    @SerialName("accepted_invites") val acceptedInvites: List<Invite> = emptyList(),
    val rewards: List<Reward> = emptyList(),
) {
    @Serializable
    data class Campaign(
        val code: String,
        @SerialName("qualification_days") val qualificationDays: Int,
        @SerialName("qualification_window_days") val qualificationWindowDays: Int,
        @SerialName("reward_days") val rewardDays: Int,
        @SerialName("double_sided") val doubleSided: Boolean,
    )

    @Serializable
    data class Counts(val invited: Int, val qualified: Int, val rewarded: Int)

    @Serializable
    data class Invite(
        @SerialName("claim_id") val claimId: String,
        val state: String,
        @SerialName("claimed_at") val claimedAt: String,
        @SerialName("qualified_at") val qualifiedAt: String? = null,
        @SerialName("rewarded_at") val rewardedAt: String? = null,
        @SerialName("distinct_days") val distinctDays: Int? = null,
        @SerialName("required_days") val requiredDays: Int? = null,
    )

    @Serializable
    data class Reward(
        @SerialName("instance_id") val instanceId: String,
        val state: String,
        @SerialName("earned_at") val earnedAt: String,
        @SerialName("activated_at") val activatedAt: String? = null,
        @SerialName("expires_at") val expiresAt: String? = null,
        val capability: String? = null,
        @SerialName("duration_hours") val durationHours: Int,
    )
}

@Serializable
data class ReferralClaimResult(
    @SerialName("claim_id") val claimId: String? = null,
    val state: String,
    val replayed: Boolean = false,
    @SerialName("error_code") val errorCode: String? = null,
    @SerialName("qualification_days") val qualificationDays: Int? = null,
    @SerialName("qualification_window_days") val qualificationWindowDays: Int? = null,
    @SerialName("reward_days") val rewardDays: Int? = null,
)

@Serializable
data class ReferralActivationResult(
    val activated: Boolean,
    val state: String,
    val reason: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
)

class ReferralException(val code: String) : Exception(code)

/** Reads and changes the invite programme (`referral_*_v1`, iOS `ReferralRewardsService`). */
@Singleton
class ReferralRewardsRepository @Inject constructor(private val client: SupabaseClient) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun dashboard(): ReferralDashboard =
        json.decodeFromString(ReferralDashboard.serializer(), client.postgrest.rpc("referral_dashboard_v1").data)

    suspend fun claim(code: String): ReferralClaimResult {
        val raw = client.postgrest.rpc("referral_claim_v1", buildJsonObject { put("p_code", code) }).data
        val result = json.decodeFromString(ReferralClaimResult.serializer(), raw)
        result.errorCode?.let { throw ReferralException(it) }
        return result
    }

    suspend fun activate(instanceId: String): ReferralActivationResult {
        val raw = client.postgrest.rpc("referral_activate_reward_v1", buildJsonObject { put("p_instance", instanceId) }).data
        return json.decodeFromString(ReferralActivationResult.serializer(), raw)
    }

    /** Best effort, like iOS: a lost analytics event never interrupts the screen. */
    suspend fun track(event: String, context: Map<String, String> = emptyMap()) {
        runCatching {
            client.postgrest.rpc("referral_event_v1", buildJsonObject {
                put("p_event", event)
                putJsonObject("p_context") { context.forEach { (key, value) -> put(key, value) } }
            })
        }
    }

    companion object {
        /** The iOS copy for each refusal; the server code travels in the exception text. */
        fun message(error: Throwable): String {
            val value = ((error as? ReferralException)?.code ?: error.message.orEmpty()).uppercase()
            return when {
                "SELF_REFERRAL" in value -> "Kendi davet kodunu kullanamazsın."
                "ALREADY_CLAIMED" in value -> "Bu hesap daha önce bir davet kodu kullandı."
                "CYCLE_DETECTED" in value -> "Karşılıklı davet kullanılamaz."
                "INVALID_REFERRAL_CODE" in value || "ACCESS_DENIED" in value -> "Davet kodu bulunamadı veya artık geçerli değil."
                "CAMPAIGN_UNAVAILABLE" in value || "FEATURE_UNAVAILABLE" in value -> "Davet programı şu an kullanılamıyor. Biraz sonra tekrar dene."
                "RATE_LIMITED" in value -> "Çok fazla kod denemesi yapıldı. Bir saat sonra tekrar deneyebilirsin."
                else -> "İşlem tamamlanamadı. İnternet bağlantını kontrol edip tekrar dene."
            }
        }

        private val CODE = Regex("^[A-Z0-9]{6,12}$")
        fun isValidCode(value: String) = CODE.matches(value)
    }
}

/**
 * An invite code that arrived through `io.supabase.riskdetected://invite?code=…` (iOS
 * `ReferralDeepLinkStore`): kept until claimed, and [openRequested] asks the profile to show the invite page.
 */
@Singleton
class ReferralDeepLinkStore @Inject constructor(@ApplicationContext private val context: Context) {
    private val prefs by lazy { context.getSharedPreferences("rd_referral", Context.MODE_PRIVATE) }
    private val _openRequested = MutableStateFlow(false)
    val openRequested: StateFlow<Boolean> = _openRequested.asStateFlow()

    val pendingCode: String?
        get() = prefs.getString(KEY, null)?.trim()?.uppercase()?.takeIf(ReferralRewardsRepository::isValidCode)

    /** Returns whether [scheme]/[host] was an invite link carrying a well-formed code. */
    fun capture(scheme: String?, host: String?, code: String?): Boolean {
        if (scheme != SCHEME || host != "invite") return false
        val value = code?.trim()?.uppercase()?.takeIf(ReferralRewardsRepository::isValidCode) ?: return false
        prefs.edit().putString(KEY, value).apply()
        requestOpen()
        return true
    }

    fun requestOpen() { _openRequested.value = true }

    fun consumeOpen() { _openRequested.value = false }

    fun clear() { prefs.edit().remove(KEY).apply() }

    companion object {
        const val SCHEME = "io.supabase.riskdetected"
        private const val KEY = "pending_code"
    }
}
