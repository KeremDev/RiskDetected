package com.riskdetectedan.app.bootstrap

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.auth.AuthRouteHold
import com.riskdetectedan.core.data.onboarding.OnboardingAnswersRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
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

    /** [routeHeld]: a session the sign-in surface is still finishing (a reset before its new
     * password, see [AuthRouteHold]) keeps Auth on screen. */
    fun sessionChanged(current: BootstrapState, isAuthenticated: Boolean, routeHeld: Boolean = false): BootstrapState = when {
        current == BootstrapState.Auth && isAuthenticated && !routeHeld -> BootstrapState.Main
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
    private val onboardingAnswersRepository: OnboardingAnswersRepository,
    private val authRouteHold: AuthRouteHold,
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

            var signedIn: String? = authRepository.currentUserId
            combine(authRepository.currentUserIdFlow, authRouteHold.held) { userId, held -> userId to held }
                .collectLatest { (userId, held) ->
                    if (userId != null) store.markAuthenticated()
                    // A new session sends the onboarding answers kept on the device right away
                    // (iOS AppState's session sink); MainActivity's resume retries a failed send.
                    if (userId != null && userId != signedIn) viewModelScope.launch { onboardingAnswersRepository.syncPending() }
                    signedIn = userId
                    _state.value = BootstrapReducer.sessionChanged(_state.value, userId != null, held)
                }
        }
    }

    fun finishOnboarding() {
        store.markOnboardingCompleted()
        _state.value = if (authRepository.currentUserId != null) BootstrapState.Main else BootstrapState.Auth
    }

    /** Pilot funnel's "Giriş yap" / skip: the sign-in surface without completing onboarding
     * (iOS NovaPilotEntryGate keeps its completion flag unset until the funnel finishes). */
    fun openLogin() {
        _state.value = if (authRepository.currentUserId != null) BootstrapState.Main else BootstrapState.Auth
    }

    /** Pilot funnel finish: the answers are already the pending draft; a signed-in account syncs
     * it now, a signed-out one when the session arrives (MainActivity's resume retry). */
    fun finishNovaOnboarding() {
        if (authRepository.currentUserId != null) viewModelScope.launch { onboardingAnswersRepository.syncPending() }
        finishOnboarding()
    }

    fun authenticated() {
        if (_state.value == BootstrapState.Auth) _state.value = BootstrapState.Main
    }

    fun accountDeleted() {
        store.markOnboardingCompleted()
        _state.value = BootstrapState.Auth
    }

}
