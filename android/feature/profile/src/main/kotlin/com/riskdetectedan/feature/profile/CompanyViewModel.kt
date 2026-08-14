package com.riskdetectedan.feature.profile

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.analysis.PlanCapabilitiesRepository
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.company.CompanyDraft
import com.riskdetectedan.core.data.company.CompanyRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.designsystem.R as RdR
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface CompanyListUiState {
    data object Loading : CompanyListUiState
    data class Loaded(val companies: List<Company>) : CompanyListUiState
    data class Failed(val error: AppErrorMessage) : CompanyListUiState
}

@HiltViewModel
class CompanyViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val companyRepository: CompanyRepository,
    private val profileRepository: ProfileRepository,
    private val planCapabilitiesRepository: PlanCapabilitiesRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<CompanyListUiState>(CompanyListUiState.Loading)
    val state: StateFlow<CompanyListUiState> = _state.asStateFlow()

    private val _saveError = MutableStateFlow<AppErrorMessage?>(null)
    val saveError: StateFlow<AppErrorMessage?> = _saveError.asStateFlow()

    private val _capabilities = MutableStateFlow(PlanCapabilities.forTier(SubscriptionTier.Free))
    val capabilities: StateFlow<PlanCapabilities> = _capabilities.asStateFlow()

    init {
        load()
    }

    fun load() {
        _state.value = CompanyListUiState.Loading
        viewModelScope.launch {
            val userId = authRepository.currentUserId
            val tier = if (userId == null) {
                SubscriptionTier.Free
            } else {
                (profileRepository.fetchProfile(userId) as? RdResult.Success)?.value?.tier
                    ?: SubscriptionTier.Free
            }
            _capabilities.value = (planCapabilitiesRepository.fetchCapabilities(tier) as? RdResult.Success)?.value
                ?: PlanCapabilities.forTier(tier)
            _state.value = when (val result = companyRepository.listCompanies()) {
                is RdResult.Success -> CompanyListUiState.Loaded(result.value)
                is RdResult.Failure -> CompanyListUiState.Failed(
                    AppErrorMessages.make(
                        result.message,
                        context = context.getString(RdR.string.rd_firma_islemi_tamamlanamadi),
                    ),
                )
            }
        }
    }

    /** [logoJpegBytes] is optional and, when present, uploaded *after* the company row exists
     * — mirrors CompanyService.swift's flow (uploadLogo needs a real companyID for its storage
     * path), so a new company is always created first without a logo, then updated with
     * `logo_path` once the upload succeeds. A failed logo upload doesn't roll back the company
     * itself (matches iOS: the company is a real, usable row either way; the logo is best-effort). */
    fun addCompany(draft: CompanyDraft, logoJpegBytes: ByteArray? = null) {
        val userId = authRepository.currentUserId ?: return
        val companyCount = (_state.value as? CompanyListUiState.Loaded)?.companies?.size ?: 0
        if (_capabilities.value.companyLimit <= companyCount) {
            _saveError.value = AppErrorMessages.make(
                context.getString(RdR.string.rd_firma_limiti_doldu),
                context = context.getString(RdR.string.rd_firma_islemi_tamamlanamadi),
            )
            return
        }
        viewModelScope.launch {
            saveCompany(userId, draft, logoJpegBytes)
        }
    }

    fun updateCompany(draft: CompanyDraft, logoJpegBytes: ByteArray? = null) {
        val userId = authRepository.currentUserId ?: return
        if (draft.id == null) return
        viewModelScope.launch { saveCompany(userId, draft, logoJpegBytes) }
    }

    /** Product-level delete is a recoverable soft delete (`is_archived=true`). Archived rows are
     * excluded by [CompanyRepository.listCompanies], so the company disappears immediately
     * without breaking historical analyses and reports that still reference its id. */
    fun deleteCompany(company: Company) {
        viewModelScope.launch {
            when (val result = companyRepository.archiveCompany(company.id)) {
                is RdResult.Success -> {
                    _saveError.value = null
                    val current = _state.value as? CompanyListUiState.Loaded
                    if (current != null) {
                        _state.value = current.copy(companies = current.companies.filterNot { it.id == company.id })
                    } else {
                        load()
                    }
                }
                is RdResult.Failure -> _saveError.value = AppErrorMessages.make(
                    result.message,
                    context = context.getString(RdR.string.rd_firma_islemi_tamamlanamadi),
                )
            }
        }
    }

    private suspend fun saveCompany(userId: String, draft: CompanyDraft, logoJpegBytes: ByteArray?) {
        val saved = when (val result = companyRepository.saveCompany(userId, draft)) {
            is RdResult.Success -> result.value
            is RdResult.Failure -> {
                _saveError.value = AppErrorMessages.make(
                    result.message,
                    context = context.getString(RdR.string.rd_firma_islemi_tamamlanamadi),
                )
                return
            }
        }
        _saveError.value = null

        if (logoJpegBytes != null) {
            when (val upload = companyRepository.uploadLogo(userId, saved.id, logoJpegBytes)) {
                is RdResult.Success -> companyRepository.saveCompany(
                    userId,
                    draft.copy(id = saved.id, logoPath = upload.value),
                )
                is RdResult.Failure -> _saveError.value = AppErrorMessages.make(
                    upload.message,
                    context = context.getString(RdR.string.rd_firma_islemi_tamamlanamadi),
                )
            }
        }
        load()
    }
}
