package com.riskdetectedan.app.account

import androidx.compose.runtime.Composable
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.auth.WelcomeEmailRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Mirrors AppState.swift's `sendWelcomeEmailIfPossible()` — same trigger (every authenticated
 * session) and same fire-and-forget contract as [LegalAcceptanceRecorder], kept as its own
 * ViewModel rather than folded into that one: unrelated concerns (welcome email vs. legal
 * audit) that only happen to share a trigger point, same one-repository-per-concern separation
 * this codebase uses elsewhere (DeviceTokenRepository vs. NotificationPreferencesRepository).
 * Delivery dedup is entirely server-side (see WelcomeEmailRepository's doc comment) — this
 * fires on every session, same as iOS.
 */
@HiltViewModel
class WelcomeEmailSenderViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val welcomeEmailRepository: WelcomeEmailRepository,
) : ViewModel() {
    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) {
                    welcomeEmailRepository.sendIfNeeded()
                }
            }
        }
    }
}

@Composable
fun WelcomeEmailSender(viewModel: WelcomeEmailSenderViewModel = hiltViewModel()) {
    // No UI — the ViewModel's init block does the work.
}
