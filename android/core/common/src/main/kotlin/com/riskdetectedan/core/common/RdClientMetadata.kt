package com.riskdetectedan.core.common

import java.util.Locale

/**
 * Kotlin mirror of App/Services/AnalysisService.swift's `AppClientMetadata` enum — same keys,
 * same values, per contracts/mobile/api/client-capabilities.md (F5). Sent on every request to
 * `analyze` / `generate-excel-report` / `register-report`, both platforms.
 *
 * NOT a `RdEnvironmentConfig` field (unlike googleWebClientId) because these values don't vary
 * by build type/environment — they vary by which client-side features actually exist, which is
 * a source-code fact, not a per-environment config fact.
 */
object RdClientMetadata {
    const val API_CONTRACT_VERSION = 3
    const val PLATFORM = "android"

    /**
     * Android's locale/safety contract is resolved at request time so changing the device/app
     * language cannot leave a long-lived repository sending stale Turkish metadata. The profile
     * IDs and defaults mirror `App/Generated/SafetyProfiles.generated.swift` exactly.
     *
     * Unsupported UI languages intentionally fall back to Turkish: Turkish is Android's base
     * resource set, while English is the only localized resource set currently shipped.
     */
    fun localization(locale: Locale = Locale.getDefault()): RdLocalizationContext {
        if (!locale.language.equals("en", ignoreCase = true)) {
            return RdLocalizationContext(
                appLanguage = "tr",
                contentLocale = "tr-TR",
                workJurisdictionCountry = "TR",
                safetyProfileId = "tr-tr-current-v1",
                safetyProfileVersion = 1,
                defaultRiskMethod = "fine_kinney",
                legalDocumentSetId = "tr-android-v1",
            )
        }

        return when (locale.country.uppercase(Locale.ROOT)) {
            "GB" -> englishContext("en-GB", "GB", "en-gb-generic-v1")
            "US" -> englishContext("en-US", "US", "en-us-generic-v1")
            "AU" -> englishContext("en-AU", "AU", "en-au-generic-v1")
            "CA" -> englishContext("en-CA", "CA", "en-ca-generic-v1")
            else -> englishContext("en-001", "INTL", "en-intl-generic-v1")
        }
    }

    fun localizationForSafetyProfile(safetyProfileId: String): RdLocalizationContext? = when (safetyProfileId) {
        "tr-tr-current-v1" -> RdLocalizationContext(
            appLanguage = "tr",
            contentLocale = "tr-TR",
            workJurisdictionCountry = "TR",
            safetyProfileId = safetyProfileId,
            safetyProfileVersion = 1,
            defaultRiskMethod = "fine_kinney",
            legalDocumentSetId = "tr-android-v1",
        )
        "en-intl-generic-v1" -> englishContext("en-001", "INTL", safetyProfileId)
        "en-gb-generic-v1" -> englishContext("en-GB", "GB", safetyProfileId)
        "en-us-generic-v1" -> englishContext("en-US", "US", safetyProfileId)
        "en-au-generic-v1" -> englishContext("en-AU", "AU", safetyProfileId)
        "en-ca-generic-v1" -> englishContext("en-CA", "CA", safetyProfileId)
        else -> null
    }

    private fun englishContext(
        contentLocale: String,
        workJurisdictionCountry: String,
        safetyProfileId: String,
    ) = RdLocalizationContext(
        appLanguage = "en",
        contentLocale = contentLocale,
        workJurisdictionCountry = workJurisdictionCountry,
        safetyProfileId = safetyProfileId,
        safetyProfileVersion = 1,
        defaultRiskMethod = "matrix_5x5",
        legalDocumentSetId = "en-global-v1",
    )

    val APP_LANGUAGE: String get() = localization().appLanguage
    val CONTENT_LOCALE: String get() = localization().contentLocale
    val WORK_JURISDICTION_COUNTRY: String get() = localization().workJurisdictionCountry
    val SAFETY_PROFILE_ID: String get() = localization().safetyProfileId
    val SAFETY_PROFILE_VERSION: Int get() = localization().safetyProfileVersion
    val DEFAULT_RISK_METHOD: String get() = localization().defaultRiskMethod
    val LEGAL_DOCUMENT_SET_ID: String get() = localization().legalDocumentSetId

    /**
     * See contracts/mobile/api/client-capabilities.md for the fail-closed-per-key rule and why
     * `global_localization_wave1` is true only because the build now ships a complete English
     * resource set and locale-aware API/report/legal metadata. Resource parity is enforced by
     * the localization verification task.
     */
    val capabilities: Map<String, Boolean> = mapOf(
        "multi_photo_analysis" to true,
        "multi_photo_coverage_v2" to true,
        "editable_findings" to true,
        "report_snapshot_v2" to true,
        "safety_claim_v4_scoreless" to true,
        "analysis_result_hub_v1" to true,
        "global_localization_wave1" to true,
    )
}

data class RdLocalizationContext(
    val appLanguage: String,
    val contentLocale: String,
    val workJurisdictionCountry: String,
    val safetyProfileId: String,
    val safetyProfileVersion: Int,
    val defaultRiskMethod: String,
    val legalDocumentSetId: String,
)
