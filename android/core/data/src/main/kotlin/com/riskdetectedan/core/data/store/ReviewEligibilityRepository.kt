package com.riskdetectedan.core.data.store

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/** Store-neutral eligibility; the app module owns the Play Review UI. */
@Singleton
class ReviewEligibilityRepository @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val _requestPending = MutableStateFlow(false)
    val requestPending: StateFlow<Boolean> = _requestPending.asStateFlow()

    init {
        if (!preferences.contains(KEY_FIRST_OPEN)) {
            preferences.edit().putLong(KEY_FIRST_OPEN, System.currentTimeMillis()).apply()
        }
        updateEligibility(System.currentTimeMillis())
    }

    fun recordSuccessfulReport(reportId: String, nowMillis: Long = System.currentTimeMillis()) {
        if (reportId.isBlank()) return
        val recordedIds = preferences.getStringSet(KEY_RECORDED_REPORT_IDS, emptySet()).orEmpty()
        if (reportId in recordedIds) return
        val count = preferences.getInt(KEY_REPORT_COUNT, 0) + 1
        preferences.edit()
            .putInt(KEY_REPORT_COUNT, count)
            .putStringSet(
                KEY_RECORDED_REPORT_IDS,
                (recordedIds + reportId).toList().takeLast(MAX_RECORDED_IDS).toSet(),
            )
            .apply()
        updateEligibility(nowMillis)
    }

    fun wasRequestedForVersion(versionCode: Int): Boolean =
        preferences.getInt(KEY_REQUESTED_VERSION, -1) == versionCode

    fun markRequested(versionCode: Int) {
        preferences.edit().putInt(KEY_REQUESTED_VERSION, versionCode).apply()
        _requestPending.value = false
    }

    fun postpone() {
        _requestPending.value = false
    }

    private fun updateEligibility(nowMillis: Long) {
        val count = preferences.getInt(KEY_REPORT_COUNT, 0)
        val firstOpen = preferences.getLong(KEY_FIRST_OPEN, nowMillis)
        val oldEnough = nowMillis - firstOpen >= TimeUnit.DAYS.toMillis(7)
        if (count >= 3 && oldEnough) _requestPending.value = true
    }

    private companion object {
        const val PREFERENCES = "rd_store_review"
        const val KEY_FIRST_OPEN = "first_open_at"
        const val KEY_REPORT_COUNT = "successful_report_count"
        const val KEY_RECORDED_REPORT_IDS = "successful_report_ids"
        const val KEY_REQUESTED_VERSION = "requested_version_code"
        const val MAX_RECORDED_IDS = 50
    }
}
