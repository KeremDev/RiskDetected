package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.DailyQuotaUsage
import com.riskdetectedan.core.data.analysis.QuotaRepository
import com.riskdetectedan.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Mirrors HomeView.swift's `loadQuotaUsage()` load side (Faz P) — not the UserDefaults cache
 * fallback, see [QuotaRepository]'s doc comment. `quota == null` covers both "not loaded yet"
 * and "fetch failed" the same way iOS's un-cached path does when there's nothing to fall back to.
 */
@HiltViewModel
class QuotaViewModel @Inject constructor(
    private val quotaRepository: QuotaRepository,
    private val authRepository: AuthRepository,
) : ViewModel() {

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
                is RdResult.Success -> _quota.value = result.value
                is RdResult.Failure -> Unit // keep the last known value, matches iOS's no-cache fallback here
            }
        }
    }
}
