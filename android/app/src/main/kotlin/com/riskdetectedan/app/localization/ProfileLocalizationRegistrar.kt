package com.riskdetectedan.app.localization

import androidx.compose.runtime.Composable
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.profile.ProfileLocalizationRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Writes the profile locale contract for every authenticated session, mirroring what
 * `AuthService.swift` does on iOS at auth time. Onboarding already writes it for accounts that
 * complete the answers step; this covers the rest — sign-ins on an account created before that
 * write existed, and hand-offs where the onboarding draft never synced — because a profile with
 * no `app_language` receives no transactional push at all (see
 * [ProfileLocalizationRepository]).
 *
 * Same reactive-recorder shape as LegalAcceptanceRecorder/PushTokenRegistrar: composed once from
 * MainActivity, no UI, and repair-only so it is a cheap no-op for an already-correct profile.
 */
@HiltViewModel
class ProfileLocalizationRegistrarViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val profileLocalizationRepository: ProfileLocalizationRepository,
) : ViewModel() {
    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) profileLocalizationRepository.ensureLocalizationContext(userId)
            }
        }
    }
}

@Composable
fun ProfileLocalizationRegistrar(
    viewModel: ProfileLocalizationRegistrarViewModel = hiltViewModel(),
) {
    // No UI — the ViewModel's init block does the work, same as LegalAcceptanceRecorder.
}
