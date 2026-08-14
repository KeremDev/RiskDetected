package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.profile.SubscriptionTier
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
private data class PlanCapabilityRuleRow(
    @SerialName("max_photos_per_analysis") val maxPhotosPerAnalysis: Int? = null,
    @SerialName("visible_photo_slots_in_ui") val visiblePhotoSlotsInUI: Int? = null,
    @SerialName("max_findings_per_photo") val maxFindingsPerPhoto: Int? = null,
    @SerialName("max_findings_per_analysis") val maxFindingsPerAnalysis: Int? = null,
    @SerialName("can_use_multi_photo_analysis") val canUseMultiPhotoAnalysis: Boolean? = null,
    @SerialName("can_edit_ai_findings") val canEditAIFindings: Boolean? = null,
    @SerialName("can_add_manual_findings") val canAddManualFindings: Boolean? = null,
)

@Serializable
private data class MultiPhotoFlagsValue(
    @SerialName("kill_switch") val killSwitch: Boolean? = null,
    @SerialName("rollout_mode") val rolloutMode: String? = null,
    @SerialName("enabled_android_builds") val enabledAndroidBuilds: List<String>? = null,
    @SerialName("min_android_build") val minAndroidBuild: Int? = null,
    val features: MultiPhotoFeatures? = null,
    @SerialName("enable_multi_photo_analysis") val enableMultiPhotoAnalysis: Boolean? = null,
    @SerialName("enable_plus_pro_5_photo_limit") val enablePlusPro5PhotoLimit: Boolean? = null,
    @SerialName("enable_photo_limit_locked_slots_for_free") val enablePhotoLimitLockedSlotsForFree: Boolean? = null,
    @SerialName("enable_editable_findings") val enableEditableFindings: Boolean? = null,
    @SerialName("enable_manual_finding_add") val enableManualFindingAdd: Boolean? = null,
    @SerialName("max_photo_count_free") val maxPhotoCountFree: Int? = null,
    @SerialName("max_photo_count_plus") val maxPhotoCountPlus: Int? = null,
    @SerialName("max_photo_count_pro") val maxPhotoCountPro: Int? = null,
    @SerialName("max_findings_per_photo") val maxFindingsPerPhoto: Int? = null,
)

@Serializable
private data class MultiPhotoFeatures(
    @SerialName("multi_photo_analysis") val multiPhotoAnalysis: Boolean? = null,
    @SerialName("plus_pro_5_photo_limit") val plusPro5PhotoLimit: Boolean? = null,
    @SerialName("photo_limit_locked_slots_for_free") val photoLimitLockedSlotsForFree: Boolean? = null,
    @SerialName("editable_findings") val editableFindings: Boolean? = null,
    @SerialName("manual_finding_add") val manualFindingAdd: Boolean? = null,
)

@Serializable
private data class FeatureFlagRow(val value: MultiPhotoFlagsValue)

enum class QuotaPeriod { Day, Month }

/** Complete Android plan contract. Enforcement remains server-side; these values drive only
 * affordances, labels and early validation and therefore always fail closed on missing data. */
data class PlanCapabilities(
    val tier: SubscriptionTier,
    val standardAnalysisLimit: Int,
    val detailedAnalysisLimit: Int?,
    val reportLimit: Int,
    val reportPeriod: QuotaPeriod,
    val riskAnalysisReportTrialLimit: Int?,
    val companyLimit: Int,
    val photoRetentionDays: Int?,
    val maxPhotosPerAnalysis: Int,
    val visiblePhotoSlotsInUI: Int,
    val maxFindingsPerPhoto: Int,
    val maxFindingsPerAnalysis: Int,
    val canUseMultiPhotoAnalysis: Boolean,
    val canEditAIFindings: Boolean,
    val canAddManualFindings: Boolean,
) {
    val canUseDetailedAnalysis: Boolean get() = detailedAnalysisLimit != null

    companion object {
        fun forTier(tier: SubscriptionTier): PlanCapabilities = when (tier) {
            SubscriptionTier.Free -> PlanCapabilities(
                tier = tier,
                standardAnalysisLimit = 1,
                detailedAnalysisLimit = null,
                reportLimit = 1,
                reportPeriod = QuotaPeriod.Day,
                riskAnalysisReportTrialLimit = 1,
                companyLimit = 0,
                photoRetentionDays = 7,
                maxPhotosPerAnalysis = 1,
                visiblePhotoSlotsInUI = 1,
                maxFindingsPerPhoto = 12,
                maxFindingsPerAnalysis = 12,
                canUseMultiPhotoAnalysis = false,
                canEditAIFindings = false,
                canAddManualFindings = false,
            )
            SubscriptionTier.Plus -> paid(tier, 10, 2, 150, 5, 30)
            SubscriptionTier.Pro -> paid(tier, 40, 10, 750, 25, null)
        }

        private fun paid(
            tier: SubscriptionTier,
            standardLimit: Int,
            detailedLimit: Int,
            reportLimit: Int,
            companyLimit: Int,
            retentionDays: Int?,
        ) = PlanCapabilities(
            tier = tier,
            standardAnalysisLimit = standardLimit,
            detailedAnalysisLimit = detailedLimit,
            reportLimit = reportLimit,
            reportPeriod = QuotaPeriod.Month,
            riskAnalysisReportTrialLimit = null,
            companyLimit = companyLimit,
            photoRetentionDays = retentionDays,
            // Product contract: every paid member can prepare a three-photo analysis. The remote
            // capability response may still close this during an emergency kill-switch, but a
            // transient capability fetch failure must not paint a paid account as Free (0/1).
            maxPhotosPerAnalysis = 3,
            visiblePhotoSlotsInUI = 3,
            maxFindingsPerPhoto = 13,
            maxFindingsPerAnalysis = 39,
            canUseMultiPhotoAnalysis = true,
            canEditAIFindings = false,
            canAddManualFindings = false,
        )
    }
}

internal object AndroidBuildGate {
    fun isOpen(
        killSwitch: Boolean,
        rolloutMode: String?,
        enabledBuilds: List<String>,
        minimumBuild: Int?,
        currentBuild: Int,
    ): Boolean {
        if (killSwitch) return false
        return when (rolloutMode?.lowercase()) {
            "build_allowlist" -> currentBuild.toString() in enabledBuilds ||
                enabledBuilds.mapNotNull(String::toIntOrNull).contains(currentBuild) ||
                (minimumBuild?.let { currentBuild >= it } == true)
            "min_build" -> minimumBuild?.let { currentBuild >= it } == true
            // Backend intentionally does not let the iOS-oriented global `all` mode open Android.
            else -> false
        }
    }
}

@Singleton
class PlanCapabilitiesRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
) {
    suspend fun fetchCapabilities(tier: SubscriptionTier): RdResult<PlanCapabilities> = try {
        val rule = client.postgrest.from("plan_capability_rules")
            .select(
                Columns.list(
                    "max_photos_per_analysis",
                    "visible_photo_slots_in_ui",
                    "max_findings_per_photo",
                    "max_findings_per_analysis",
                    "can_use_multi_photo_analysis",
                    "can_edit_ai_findings",
                    "can_add_manual_findings",
                ),
            ) {
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

        val base = PlanCapabilities.forTier(tier)
        val releaseGateOpen = AndroidBuildGate.isOpen(
            killSwitch = flags.killSwitch == true,
            rolloutMode = flags.rolloutMode,
            enabledBuilds = flags.enabledAndroidBuilds.orEmpty(),
            minimumBuild = flags.minAndroidBuild,
            currentBuild = environmentConfig.appVersionCode,
        )
        val multiPhotoFlag = flags.features?.multiPhotoAnalysis ?: flags.enableMultiPhotoAnalysis ?: false
        val paidLimitFlag = flags.features?.plusPro5PhotoLimit ?: flags.enablePlusPro5PhotoLimit ?: false
        val paidMultiPhotoEnabled = tier.isPaid && releaseGateOpen && multiPhotoFlag && paidLimitFlag
        val flagPhotoLimit = when (tier) {
            SubscriptionTier.Free -> flags.maxPhotoCountFree ?: 1
            SubscriptionTier.Plus -> flags.maxPhotoCountPlus ?: 1
            SubscriptionTier.Pro -> flags.maxPhotoCountPro ?: 1
        }
        val resolvedPhotos = if (tier.isPaid && paidMultiPhotoEnabled) {
            minOf(rule.maxPhotosPerAnalysis ?: 1, flagPhotoLimit)
        } else {
            minOf(rule.maxPhotosPerAnalysis ?: 1, if (tier.isPaid) 1 else flags.maxPhotoCountFree ?: 1)
        }.coerceIn(1, 3)
        val resolvedPerPhoto = minOf(
            rule.maxFindingsPerPhoto ?: base.maxFindingsPerPhoto,
            flags.maxFindingsPerPhoto ?: base.maxFindingsPerPhoto,
        ).coerceAtLeast(1)
        val resolvedTotal = minOf(
            rule.maxFindingsPerAnalysis ?: resolvedPerPhoto,
            resolvedPhotos * resolvedPerPhoto,
        ).coerceAtLeast(1)
        val showLockedFreeSlots = tier == SubscriptionTier.Free && releaseGateOpen &&
            (flags.features?.photoLimitLockedSlotsForFree
                ?: flags.enablePhotoLimitLockedSlotsForFree
                ?: false)
        val editEnabled = releaseGateOpen &&
            (flags.features?.editableFindings ?: flags.enableEditableFindings ?: false) &&
            rule.canEditAIFindings == true
        val manualEnabled = releaseGateOpen &&
            (flags.features?.manualFindingAdd ?: flags.enableManualFindingAdd ?: false) &&
            rule.canAddManualFindings == true

        RdResult.Success(
            base.copy(
                maxPhotosPerAnalysis = resolvedPhotos,
                visiblePhotoSlotsInUI = if (paidMultiPhotoEnabled || showLockedFreeSlots) {
                    (rule.visiblePhotoSlotsInUI ?: 1).coerceIn(1, 3)
                } else {
                    1
                },
                maxFindingsPerPhoto = resolvedPerPhoto,
                maxFindingsPerAnalysis = resolvedTotal,
                canUseMultiPhotoAnalysis = paidMultiPhotoEnabled && rule.canUseMultiPhotoAnalysis == true,
                canEditAIFindings = editEnabled,
                canAddManualFindings = manualEnabled,
            ),
        )
    } catch (t: Throwable) {
        RdResult.Failure("plan_capabilities_fetch_failed", t.message ?: "plan_capabilities_fetch_failed", t)
    }
}
