package com.riskdetectedan.feature.paywall

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.billing.BillingRepository
import com.riskdetectedan.core.data.profile.SubscriptionTier
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface PaywallUiState {
    data object Loading : PaywallUiState
    data object SignedOut : PaywallUiState
    data class Loaded(val packages: List<BillingPackage>, val currentTier: SubscriptionTier) : PaywallUiState
    data class Failed(val message: String) : PaywallUiState
}

/**
 * Mirrors `RevenueCatSubscriptionManager`'s configure -> identify -> loadOfferings sequence
 * (SubscriptionManager.swift) via [BillingRepository]. No pricing/trial-length UI logic lives
 * here — that's server/store-configured (DEC-04 coordinates trial length across platforms,
 * DEC-14 requires identical Play/App Store product ids), this just displays what the store
 * actually returns and reports what the store actually granted after a purchase.
 */
@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val billingRepository: BillingRepository,
) : ViewModel() {

    private val _state = MutableStateFlow<PaywallUiState>(PaywallUiState.Loading)
    val state: StateFlow<PaywallUiState> = _state.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _purchaseError = MutableStateFlow<String?>(null)
    val purchaseError: StateFlow<String?> = _purchaseError.asStateFlow()

    init {
        load()
    }

    fun load() {
        val userId = authRepository.currentUserId
        if (userId == null) {
            _state.value = PaywallUiState.SignedOut
            return
        }
        _state.value = PaywallUiState.Loading
        viewModelScope.launch {
            when (val configured = billingRepository.configure(userId)) {
                is RdResult.Failure -> {
                    _state.value = PaywallUiState.Failed(configured.message)
                    return@launch
                }
                is RdResult.Success -> Unit
            }

            val packages = when (val result = billingRepository.fetchPackages()) {
                is RdResult.Success -> result.value
                is RdResult.Failure -> {
                    _state.value = PaywallUiState.Failed(result.message)
                    return@launch
                }
            }
            val tier = when (val result = billingRepository.currentTier()) {
                is RdResult.Success -> result.value
                // A completed offerings fetch with an unreadable customer-info read is still
                // worth showing — surface Free rather than fail the whole paywall over what's
                // likely a transient read error (same reasoning as AnalysisViewModel's findings
                // fallback).
                is RdResult.Failure -> SubscriptionTier.Free
            }
            _state.value = PaywallUiState.Loaded(packages, tier)
        }
    }

    fun purchase(activity: Activity, billingPackage: BillingPackage) {
        if (_isPurchasing.value) return
        _isPurchasing.value = true
        _purchaseError.value = null
        viewModelScope.launch {
            when (val result = billingRepository.purchase(activity, billingPackage)) {
                is RdResult.Success -> {
                    _isPurchasing.value = false
                    val current = _state.value as? PaywallUiState.Loaded
                    if (current != null) _state.value = current.copy(currentTier = result.value)
                }
                is RdResult.Failure -> {
                    _isPurchasing.value = false
                    _purchaseError.value = result.message
                }
            }
        }
    }

    fun restorePurchases() {
        if (_isPurchasing.value) return
        _isPurchasing.value = true
        _purchaseError.value = null
        viewModelScope.launch {
            when (val result = billingRepository.restorePurchases()) {
                is RdResult.Success -> {
                    _isPurchasing.value = false
                    val current = _state.value as? PaywallUiState.Loaded
                    if (current != null) _state.value = current.copy(currentTier = result.value)
                }
                is RdResult.Failure -> {
                    _isPurchasing.value = false
                    _purchaseError.value = result.message
                }
            }
        }
    }

    fun clearPurchaseError() {
        _purchaseError.value = null
    }
}
