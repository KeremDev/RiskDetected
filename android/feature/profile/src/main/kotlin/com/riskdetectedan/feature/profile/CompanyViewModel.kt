package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.company.CompanyDraft
import com.riskdetectedan.core.data.company.CompanyRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface CompanyListUiState {
    data object Loading : CompanyListUiState
    data class Loaded(val companies: List<Company>) : CompanyListUiState
    data class Failed(val message: String) : CompanyListUiState
}

@HiltViewModel
class CompanyViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val companyRepository: CompanyRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<CompanyListUiState>(CompanyListUiState.Loading)
    val state: StateFlow<CompanyListUiState> = _state.asStateFlow()

    private val _saveError = MutableStateFlow<String?>(null)
    val saveError: StateFlow<String?> = _saveError.asStateFlow()

    init {
        load()
    }

    fun load() {
        _state.value = CompanyListUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = companyRepository.listCompanies()) {
                is RdResult.Success -> CompanyListUiState.Loaded(result.value)
                is RdResult.Failure -> CompanyListUiState.Failed(result.message)
            }
        }
    }

    fun addCompany(draft: CompanyDraft) {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch {
            when (val result = companyRepository.saveCompany(userId, draft)) {
                is RdResult.Success -> {
                    _saveError.value = null
                    load()
                }
                is RdResult.Failure -> _saveError.value = result.message
            }
        }
    }
}
