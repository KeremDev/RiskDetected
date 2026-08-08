package com.riskdetectedan.app.push

import androidx.compose.runtime.Composable
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.messaging.FirebaseMessaging
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.notifications.DeviceTokenRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject

/**
 * Covers the registration case [RdFirebaseMessagingService.onNewToken] can't: an already-issued
 * FCM token (e.g. from a fresh install, before the user ever signed in) plus an already
 * signed-in session — `onNewToken` only fires for genuinely *new* tokens, not on every launch or
 * sign-in, unlike APNs device tokens on iOS.
 *
 * Reactive on [AuthRepository.currentUserIdFlow] (same shape as [LegalAcceptanceRecorder]/
 * `WelcomeEmailSender`, composed once from `MainActivity` so it lives for the process) rather
 * than a one-shot `init`-time snapshot — this closes a previously-documented gap: a fresh sign-in
 * within the same app session now registers the token immediately instead of waiting for the
 * next launch or an incidental `onNewToken` firing. No feature-module coupling needed to get
 * this — the existing app-level reactive-recorder pattern already covers it.
 */
@HiltViewModel
class PushTokenRegistrarViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val deviceTokenRepository: DeviceTokenRepository,
) : ViewModel() {
    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) {
                    val token = try {
                        FirebaseMessaging.getInstance().token.await()
                    } catch (t: Throwable) {
                        null
                    }
                    if (token != null) {
                        deviceTokenRepository.registerToken(userId, token, notificationsEnabled = true)
                    }
                }
            }
        }
    }
}

@Composable
fun PushTokenRegistrar(viewModel: PushTokenRegistrarViewModel = hiltViewModel()) {
    // No UI — the ViewModel's init block does the work. Composing this once (see MainActivity)
    // is enough to create/retain it for the process lifetime.
}
