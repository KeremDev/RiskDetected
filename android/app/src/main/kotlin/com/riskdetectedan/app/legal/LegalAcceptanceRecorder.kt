package com.riskdetectedan.app.legal

import androidx.compose.runtime.Composable
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.legal.LegalAcceptanceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Mirrors AppState.swift's session `.sink` calling `LegalAcceptanceService.shared
 * .recordLoginNoticeAcceptanceIfNeeded(userID:)` on every authenticated session emission — a
 * reactive observer on [AuthRepository.currentUserIdFlow] rather than [PushTokenRegistrar]'s
 * launch-time-only snapshot, since a legal audit record ideally lands right after sign-up/
 * sign-in, not on the next app launch. (The repository itself dedupes by user id, so repeat
 * emissions for the same already-recorded user are cheap no-ops — safe to just react to every
 * change without extra bookkeeping here.)
 */
@HiltViewModel
class LegalAcceptanceRecorderViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val legalAcceptanceRepository: LegalAcceptanceRepository,
) : ViewModel() {
    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) {
                    legalAcceptanceRepository.recordLoginNoticeAcceptanceIfNeeded(userId)
                }
            }
        }
    }
}

@Composable
fun LegalAcceptanceRecorder(viewModel: LegalAcceptanceRecorderViewModel = hiltViewModel()) {
    // No UI — the ViewModel's init block does the work. Composing this once (see MainActivity)
    // is enough to create/retain it for the process lifetime.
}
