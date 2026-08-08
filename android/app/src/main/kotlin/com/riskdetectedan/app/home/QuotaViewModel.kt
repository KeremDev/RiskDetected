package com.riskdetectedan.app.home

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.DailyQuotaUsage
import com.riskdetectedan.core.data.analysis.QuotaRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject

/**
 * Mirrors HomeView.swift's `loadQuotaUsage()` load side (Faz P) — including the UserDefaults
 * cache fallback (added after Faz P shipped): `cacheQuotaUsage`/`cachedQuotaUsageForCurrentUser`/
 * `quotaCacheKeyForCurrentUser`/`istanbulDayKey()`, ported verbatim as a SharedPreferences-backed
 * cache (same `@ApplicationContext`-injection pattern as `DeviceTokenRepository`'s
 * `installation_id`). Key shape matches exactly: `"rd.home.freeQuota.<userId>.<yyyy-MM-dd in
 * Europe/Istanbul>"` + `.used`/`.limit` suffixes — a fresh Istanbul calendar day naturally
 * invalidates the previous day's cached entry (never explicitly cleared, exactly like iOS).
 * `quota == null` now only means "never successfully loaded or cached", not "any failed fetch".
 */
@HiltViewModel
class QuotaViewModel @Inject constructor(
    private val quotaRepository: QuotaRepository,
    private val authRepository: AuthRepository,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val prefs by lazy { context.getSharedPreferences("rd_home_free_quota", Context.MODE_PRIVATE) }

    private val _quota = MutableStateFlow<DailyQuotaUsage?>(null)
    val quota: StateFlow<DailyQuotaUsage?> = _quota.asStateFlow()

    fun refresh() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _quota.value = null
            return
        }
        viewModelScope.launch {
            when (val result = quotaRepository.dailyQuotaUsage(userId)) {
                is RdResult.Success -> {
                    _quota.value = result.value
                    cacheQuotaUsage(userId, result.value)
                }
                is RdResult.Failure -> _quota.value = cachedQuotaUsage(userId)
            }
        }
    }

    private fun cacheQuotaUsage(userId: String, usage: DailyQuotaUsage) {
        val key = quotaCacheKey(userId)
        prefs.edit()
            .putInt("$key.used", usage.used)
            .putInt("$key.limit", usage.limit)
            .apply()
    }

    private fun cachedQuotaUsage(userId: String): DailyQuotaUsage? {
        val key = quotaCacheKey(userId)
        if (!prefs.contains("$key.used") || !prefs.contains("$key.limit")) return null
        val used = prefs.getInt("$key.used", 0)
        val limit = prefs.getInt("$key.limit", 0)
        if (limit <= 0) return null
        return DailyQuotaUsage(used = used, limit = limit)
    }

    private fun quotaCacheKey(userId: String): String =
        "rd.home.freeQuota.$userId.${istanbulDayKey()}"

    private fun istanbulDayKey(): String {
        val zone = ZoneId.of("Europe/Istanbul")
        return DateTimeFormatter.ISO_LOCAL_DATE.format(LocalDate.now(zone))
    }
}
