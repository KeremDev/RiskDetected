package com.riskdetectedan.feature.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.notifications.NotificationEngagementRepository
import com.riskdetectedan.core.data.notifications.NotificationPreferencesRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Persists the notification choice made during onboarding.
 *
 * Android's POST_NOTIFICATIONS prompt is local to the device. The admin notification panel and
 * notification workers read the server-side preference row, so accepting the prompt must also
 * mirror iOS's onboarding flow by enabling the master preference and forcing an engagement sync.
 */
@HiltViewModel
class OnboardingNotificationPermissionViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val preferencesRepository: NotificationPreferencesRepository,
    private val engagementRepository: NotificationEngagementRepository,
) : ViewModel() {
    private var isRecording = false

    fun recordPermission(granted: Boolean, onComplete: () -> Unit) {
        if (isRecording) return
        isRecording = true

        viewModelScope.launch {
            try {
                authRepository.currentUserId?.let { userId ->
                    // Keep the server preference in sync with the OS choice. On denial we leave
                    // the row untouched, matching iOS and avoiding an unsolicited opt-out row.
                    if (granted) preferencesRepository.setMasterPreference(enabled = true)
                    engagementRepository.sync(userId, force = true)
                }
            } finally {
                isRecording = false
                // A backend hiccup must not trap the user in onboarding; the app-level token and
                // engagement registrars will retry on the next authenticated resume.
                onComplete()
            }
        }
    }
}
