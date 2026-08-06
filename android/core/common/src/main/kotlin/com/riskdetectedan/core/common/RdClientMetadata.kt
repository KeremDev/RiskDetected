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
    const val API_CONTRACT_VERSION = 2
    const val PLATFORM = "android"

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
        "global_localization_wave1" to false,
    )
}
