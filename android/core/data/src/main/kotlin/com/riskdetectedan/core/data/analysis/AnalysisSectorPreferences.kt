package com.riskdetectedan.core.data.analysis

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

enum class AnalysisSectorBadge { Recommended, LastUsed }

data class AnalysisSectorPickerItem(val sector: AnalysisSector, val badges: Set<AnalysisSectorBadge> = emptySet())

/**
 * Real port of `AnalysisSectorPreferences` (App/Models/AnalysisSector.swift) — closes the
 * "Home-embedded sector-picker sheet" gap documented since the Faz M-S plan closed (Android's
 * sector picker lived only inside `AnalysisScreen`, reached *after* canvas confirm; iOS shows a
 * dedicated Home-embedded sheet *before* canvas confirm — `beginPreAnalysisSelection()`). SharedPreferences-
 * backed, same pattern as every other on-device cache in this port (`DeviceTokenRepository`'s
 * `installation_id`, `QuotaViewModel`'s cache). `recommended` isn't ported — iOS's own real call
 * site (`HomeView.swift`'s `sectorPickerItems`) never passes one either, not a shortcut.
 *
 * [onboardingSectors] mirrors `onboardingSectors(from:)`, but reads a *local* cache written once
 * by [saveOnboardingSectors] rather than a server fetch — matches iOS's own source exactly:
 * `AnalysisSectorPreferences.onboardingSectors(from:)` takes `OnboardingAnswersService.shared
 * .pendingDraft()`, itself just a `UserDefaults`-cached local draft from the same onboarding
 * session, not a re-fetch from the backend (there is no "read back my onboarding answers" RPC on
 * either platform).
 */
@Singleton
class AnalysisSectorPreferences @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val prefs by lazy { context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

    fun lastUsedSector(): AnalysisSector? =
        prefs.getString(KEY_LAST_USED, null)?.let(AnalysisSector::fromId)

    fun recordLastUsed(sector: AnalysisSector) {
        prefs.edit { putString(KEY_LAST_USED, sector.id) }
    }

    /** Called once from onboarding's answer-submit step (mirrors `savePendingDraft` landing the
     * same data `onboardingSectors(from:)` later reads) — order preserved (a delimited string,
     * not a `Set`, which Android's SharedPreferences would silently reorder). */
    fun saveOnboardingSectors(sectorIds: List<String>) {
        prefs.edit { putString(KEY_ONBOARDING_SECTORS, sectorIds.joinToString(",")) }
    }

    fun onboardingSectors(): List<AnalysisSector> =
        prefs.getString(KEY_ONBOARDING_SECTORS, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?.mapNotNull(AnalysisSector::fromId)
            .orEmpty()

    /** Real port of `pickerItems(onboardingSectors:lastUsed:recommended:)` — same precedence
     * (onboarding sectors first, then last-used if not already listed, then every remaining
     * sector in catalog order, `general` always last), same de-dupe-by-first-occurrence rule. */
    fun pickerItems(): List<AnalysisSectorPickerItem> {
        val items = mutableListOf<AnalysisSectorPickerItem>()
        val seen = mutableSetOf<AnalysisSector>()
        fun append(sector: AnalysisSector, badges: Set<AnalysisSectorBadge> = emptySet()) {
            if (seen.add(sector)) items.add(AnalysisSectorPickerItem(sector, badges))
        }

        val onboarding = onboardingSectors()
        for (sector in onboarding) if (sector != AnalysisSector.General) append(sector)

        val lastUsed = lastUsedSector()
        if (lastUsed != null && lastUsed != AnalysisSector.General && lastUsed !in onboarding) {
            append(lastUsed, setOf(AnalysisSectorBadge.LastUsed))
        }

        for (sector in AnalysisSector.entries) if (sector != AnalysisSector.General) append(sector)

        append(AnalysisSector.General)
        return items
    }

    private companion object {
        const val PREFS_NAME = "rd_analysis_sector_prefs"
        const val KEY_LAST_USED = "last_used"
        const val KEY_ONBOARDING_SECTORS = "onboarding_sectors"
    }
}
