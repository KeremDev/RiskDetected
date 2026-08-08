package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.profile.SubscriptionTier
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/** Decode target for `plan_capability_rules` — same subset AppState.swift's
 * `BackendPlanCapabilityRuleRow` reads. */
@Serializable
private data class PlanCapabilityRuleRow(
    @SerialName("max_photos_per_analysis") val maxPhotosPerAnalysis: Int? = null,
    @SerialName("visible_photo_slots_in_ui") val visiblePhotoSlotsInUI: Int? = null,
)

/** Decode target for the `multi_photo_analysis` `app_feature_flags.value` jsonb — same subset
 * `BackendMultiPhotoFlags`/`BackendFeatureFlags` read (only the photo-count-relevant fields;
 * `enable_editable_findings`/`enable_manual_finding_add` deliberately not read here, see
 * [PlanCapabilitiesRepository.fetchPhotoCapabilities]'s doc comment). */
@Serializable
private data class MultiPhotoFlagsValue(
    @SerialName("kill_switch") val killSwitch: Boolean? = null,
    @SerialName("rollout_mode") val rolloutMode: String? = null,
    val features: MultiPhotoFeatures? = null,
    @SerialName("enable_multi_photo_analysis") val enableMultiPhotoAnalysis: Boolean? = null,
    @SerialName("enable_plus_pro_5_photo_limit") val enablePlusPro5PhotoLimit: Boolean? = null,
    @SerialName("enable_photo_limit_locked_slots_for_free") val enablePhotoLimitLockedSlotsForFree: Boolean? = null,
    @SerialName("max_photo_count_free") val maxPhotoCountFree: Int? = null,
    @SerialName("max_photo_count_plus") val maxPhotoCountPlus: Int? = null,
    @SerialName("max_photo_count_pro") val maxPhotoCountPro: Int? = null,
) {
    /**
     * Android-safe reinterpretation of `isReleaseGateOpenForCurrentBuild` — the real flag row
     * (checked live: `rollout_mode: "build_allowlist"`, `enabled_ios_builds: [...up to "81"]`,
     * `min_ios_build: 80`) has no Android-scoped allowlist field at all, it was never designed
     * with a second platform in mind. Porting the iOS build-number comparison verbatim would
     * either always fail closed (Android version codes never match iOS build numbers) or, worse,
     * accidentally succeed on a coincidental numeric match — the exact bug class F3 already found
     * and fixed once this session for `LocalizationRolloutContext` (13 flags reachable by a
     * colliding Android versionCode). Staying honest here: only `rollout_mode == "all"`
     * (genuinely platform-agnostic) opens the gate for Android; `build_allowlist`/`min_build`
     * modes stay closed since neither has an Android-meaningful field to check. Currently closed
     * in production for both platforms either way (mode is `build_allowlist`, not `all`).
     */
    private val isReleaseGateOpenForAndroid: Boolean
        get() = killSwitch != true && rolloutMode?.lowercase() == "all"

    val effectiveEnableMultiPhotoAnalysis: Boolean
        get() = isReleaseGateOpenForAndroid && (features?.multiPhotoAnalysis ?: enableMultiPhotoAnalysis ?: false)

    val effectiveEnablePlusPro5PhotoLimit: Boolean
        get() = isReleaseGateOpenForAndroid && (features?.plusPro5PhotoLimit ?: enablePlusPro5PhotoLimit ?: false)

    val effectiveEnablePhotoLimitLockedSlotsForFree: Boolean
        get() = isReleaseGateOpenForAndroid && (features?.photoLimitLockedSlotsForFree ?: enablePhotoLimitLockedSlotsForFree ?: false)
}

@Serializable
private data class MultiPhotoFeatures(
    @SerialName("multi_photo_analysis") val multiPhotoAnalysis: Boolean? = null,
    @SerialName("plus_pro_5_photo_limit") val plusPro5PhotoLimit: Boolean? = null,
    @SerialName("photo_limit_locked_slots_for_free") val photoLimitLockedSlotsForFree: Boolean? = null,
)

@Serializable
private data class FeatureFlagRow(val value: MultiPhotoFlagsValue)

/** Real per-tier photo-count/slot resolution — the fields Android's photo tray actually consumes
 * ([com.riskdetectedan.core.data.analysis.AnalysisCanvas]-adjacent UI: `PhotoTraySheet`/
 * `PhotoUploadCard`/gallery-picker via `HomeScreen`'s `maxPhotoCount`). Clamped 1..3, same as
 * `safeMaxPhotosPerAnalysis`/`safeVisiblePhotoSlotsInUI`. */
data class PlanPhotoCapabilities(
    val maxPhotosPerAnalysis: Int,
    val visiblePhotoSlotsInUI: Int,
)

/**
 * Real port of `AppState.swift`'s `loadRemotePlanCapabilities(for:)` — closes the "remote
 * `PlanCapabilities` override" gap documented since the Faz M-S plan closed and reaffirmed in
 * [com.riskdetectedan.app.home.HomeTierViewModel]'s doc comment. Deliberately scoped to just the
 * photo-count fields Android's UI actually reads: `canEditAIFindings`/`canAddManualFindings`
 * aren't ported here — Android's Finding CRUD UI (#13/#19/#21/#22) already ships unconditionally
 * with no local gate consulting this flag, and adding one now would risk *hiding*
 * already-shipped, already-working functionality behind a flag it was never built to respect,
 * a regression risk far outweighing the parity gain (the flag is closed in production today
 * anyway — see [MultiPhotoFlagsValue]'s doc comment).
 */
@Singleton
class PlanCapabilitiesRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun fetchPhotoCapabilities(tier: SubscriptionTier): RdResult<PlanPhotoCapabilities> = try {
        val rule = client.postgrest.from("plan_capability_rules")
            .select(Columns.list("max_photos_per_analysis", "visible_photo_slots_in_ui")) {
                filter { eq("plan", tier.name.lowercase()) }
                limit(1)
            }
            .decodeList<PlanCapabilityRuleRow>()
            .firstOrNull()

        val flags = client.postgrest.from("app_feature_flags")
            .select(Columns.list("value")) {
                filter { eq("key", "multi_photo_analysis") }
                limit(1)
            }
            .decodeList<FeatureFlagRow>()
            .firstOrNull()
            ?.value

        if (rule == null || flags == null) {
            return RdResult.Failure("plan_capabilities_unavailable", "plan_capabilities_unavailable")
        }

        val paidMultiPhotoEnabled = tier.isPaid &&
            flags.effectiveEnableMultiPhotoAnalysis &&
            flags.effectiveEnablePlusPro5PhotoLimit
        val flagPhotoLimit = when (tier) {
            SubscriptionTier.Free -> flags.maxPhotoCountFree ?: 1
            SubscriptionTier.Plus -> flags.maxPhotoCountPlus ?: 1
            SubscriptionTier.Pro -> flags.maxPhotoCountPro ?: 1
        }
        val resolvedMaxPhotos = if (tier.isPaid) {
            if (paidMultiPhotoEnabled) minOf(rule.maxPhotosPerAnalysis ?: 1, flagPhotoLimit) else 1
        } else {
            minOf(rule.maxPhotosPerAnalysis ?: 1, flags.maxPhotoCountFree ?: 1)
        }
        val shouldShowPhotoSlots = paidMultiPhotoEnabled ||
            (tier == SubscriptionTier.Free && flags.effectiveEnablePhotoLimitLockedSlotsForFree)
        val resolvedVisibleSlots = if (shouldShowPhotoSlots) (rule.visiblePhotoSlotsInUI ?: 5) else 1

        RdResult.Success(
            PlanPhotoCapabilities(
                maxPhotosPerAnalysis = resolvedMaxPhotos.coerceIn(1, 3),
                visiblePhotoSlotsInUI = resolvedVisibleSlots.coerceIn(1, 3),
            ),
        )
    } catch (t: Throwable) {
        RdResult.Failure("plan_capabilities_fetch_failed", t.message ?: "plan_capabilities_fetch_failed", t)
    }
}
