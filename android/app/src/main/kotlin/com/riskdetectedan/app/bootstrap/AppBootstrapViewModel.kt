package com.riskdetectedan.app.bootstrap

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class BootstrapState {
    Splash,
    Onboarding,
    Auth,
    Main,
    UpdateBlocked,
    LegalBlocked,
}

internal object BootstrapReducer {
    fun initial(shouldStartOnboarding: Boolean, isAuthenticated: Boolean): BootstrapState = when {
        isAuthenticated -> BootstrapState.Main
        shouldStartOnboarding -> BootstrapState.Onboarding
        else -> BootstrapState.Auth
    }

    fun sessionChanged(current: BootstrapState, isAuthenticated: Boolean): BootstrapState = when {
        current == BootstrapState.Auth && isAuthenticated -> BootstrapState.Main
        current == BootstrapState.Main && !isAuthenticated -> BootstrapState.Auth
        else -> current
    }
}

/** Android counterpart of AppState.bootstrap/finishOnboarding. ReleaseGate owns the hard-update
 * overlay and the legal service owns legal decisions; their blocked enum values remain part of
 * this one public root-state vocabulary without duplicating those services' network work here. */
@HiltViewModel
class AppBootstrapViewModel @Inject constructor(
    private val store: AppBootstrapStore,
    private val authRepository: AuthRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(BootstrapState.Splash)
    val state: StateFlow<BootstrapState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val freshInstall = store.initializeInstall()
            // ReleaseGate owns the one Supabase initialization wait before this navigation graph
            // is composed. Waiting a second time here can strand a restored release session in
            // Initializing on supabase-kt; read the restored identity immediately and keep the
            // flow below as the authority for the eventual refresh/sign-out result.
            if (freshInstall && authRepository.currentUserId != null) {
                authRepository.clearLocalSession()
            }
            if (authRepository.currentUserId != null) store.markAuthenticated()

            _state.value = BootstrapReducer.initial(
                shouldStartOnboarding = store.shouldStartOnboarding,
                isAuthenticated = authRepository.currentUserId != null,
            )

            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) store.markAuthenticated()
                _state.value = BootstrapReducer.sessionChanged(_state.value, userId != null)
            }
        }
    }

    fun finishOnboarding() {
        store.markOnboardingCompleted()
        _state.value = if (authRepository.currentUserId != null) BootstrapState.Main else BootstrapState.Auth
    }

    fun authenticated() {
        if (_state.value == BootstrapState.Auth) _state.value = BootstrapState.Main
    }

    fun accountDeleted() {
        store.markOnboardingCompleted()
        _state.value = BootstrapState.Auth
    }

}
