package com.riskdetectedan.core.data.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Keeps the app on the sign-in surface while a session exists that is not a finished sign-in yet:
 * a reset's recovery session before the new password is set. iOS holds
 * `AppState.novaPilotOnboardingActive` from `NovaPilotEntryGate` the same way.
 */
@Singleton
class AuthRouteHold @Inject constructor() {
    private val _held = MutableStateFlow(false)
    val held: StateFlow<Boolean> = _held.asStateFlow()

    fun hold() { _held.value = true }
    fun release() { _held.value = false }
}
