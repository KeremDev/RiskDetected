package com.riskdetectedan.core.common

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

    // The first Android release is deliberately Turkish-only. Keep these values together so
    // auth, analysis, reports, support and release-policy requests cannot slowly drift into
    // different locale/safety contexts. They mirror build-81's Turkey safety profile.
    const val APP_LANGUAGE = "tr"
    const val CONTENT_LOCALE = "tr-TR"
    const val WORK_JURISDICTION_COUNTRY = "TR"
    const val SAFETY_PROFILE_ID = "tr-tr-current-v1"
    const val SAFETY_PROFILE_VERSION = 1
    const val DEFAULT_RISK_METHOD = "fine_kinney"

    /**
     * See contracts/mobile/api/client-capabilities.md for the fail-closed-per-key rule and why
     * global_localization_wave1 stays false until Android has its own build-gate equivalent of
     * iOS's RDGlobalLocalizationBuildGate.isCompiledIn.
     */
    val capabilities: Map<String, Boolean> = mapOf(
        "multi_photo_analysis" to true,
        "multi_photo_coverage_v2" to true,
        "editable_findings" to true,
        "report_snapshot_v2" to true,
        "safety_claim_v4_scoreless" to true,
        "analysis_result_hub_v1" to true,
        "global_localization_wave1" to false,
    )
}
