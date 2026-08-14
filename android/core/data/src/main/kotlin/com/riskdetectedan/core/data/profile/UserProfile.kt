package com.riskdetectedan.core.data.profile

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Kotlin mirror of App/Models/UserProfile.swift — same table (`profiles`), same column names,
 * same "only id/tier are required, everything else optional so schema additions never break
 * decode" philosophy from the Swift doc comment.
 */
@Serializable
data class UserProfile(
    val id: String,
    val email: String? = null,
    @SerialName("full_name") val fullName: String? = null,
    val initials: String? = null,
    val title: String? = null,
    @SerialName("certificate_number") val certificateNumber: String? = null,
    @SerialName("company_name") val companyName: String? = null,
    @SerialName("company_logo_url") val companyLogoUrl: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    val phone: String? = null,
    val tier: SubscriptionTier,
    @SerialName("preferred_method") val preferredMethod: String? = null,
    @SerialName("daily_quota_used") val dailyQuotaUsed: Int? = null,
    @SerialName("daily_quota_reset_at") val dailyQuotaResetAt: String? = null,
    @SerialName("subscription_period") val subscriptionPeriod: String? = null,
    @SerialName("subscription_renewal_at") val subscriptionRenewalAt: String? = null,
    @SerialName("app_language") val appLanguage: String? = null,
    @SerialName("preferred_content_locale") val preferredContentLocale: String? = null,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String? = null,
    @SerialName("work_jurisdiction_region") val workJurisdictionRegion: String? = null,
    @SerialName("safety_profile_id") val safetyProfileId: String? = null,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int? = null,
    @SerialName("legal_document_set") val legalDocumentSetId: String? = null,
    @SerialName("first_seen_device_region_code") val firstSeenDeviceRegionCode: String? = null,
    @SerialName("first_seen_device_region_at") val firstSeenDeviceRegionAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
) {
    val isPro: Boolean get() = tier == SubscriptionTier.Pro
    val isPaid: Boolean get() = tier.isPaid

    val displayName: String
        get() = fullName ?: email?.substringBefore("@") ?: "Kullanıcı"

    val displayInitials: String
        get() = when {
            !initials.isNullOrEmpty() -> initials
            !fullName.isNullOrEmpty() -> fullName.trim().split(" ")
                .take(2)
                .mapNotNull { it.firstOrNull()?.uppercaseChar() }
                .joinToString("")
            else -> "—"
        }
}

@Serializable
enum class SubscriptionTier {
    @SerialName("free") Free,
    @SerialName("plus") Plus,
    @SerialName("pro") Pro,
    ;

    val isPaid: Boolean get() = this != Free
    val rank: Int get() = when (this) { Free -> 0; Plus -> 1; Pro -> 2 }

    /** Mirrors SubscriptionTier.includes(_:) — tier-gate check (e.g. "does this user's tier
     * unlock this AnalysisCanvas's minTier"). */
    fun includes(required: SubscriptionTier): Boolean = rank >= required.rank
}
