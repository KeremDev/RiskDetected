package com.riskdetectedan.app.push

import androidx.compose.runtime.Composable
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.messaging.FirebaseMessaging
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.notifications.DeviceTokenRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject

/**
 * Covers the registration case [RdFirebaseMessagingService.onNewToken] can't: an already-issued
 * FCM token (e.g. from a fresh install, before the user ever signed in) plus an already
 * signed-in session on a later app launch — `onNewToken` only fires for genuinely *new* tokens,
 * not on every launch, unlike APNs device tokens on iOS. Fires once per process (ViewModel
 * `init`, survives configuration changes, doesn't re-run on recomposition).
 *
 * **Known simplification, not silently dropped**: this doesn't re-register immediately right
 * after a fresh sign-in within the same app session (that requires wiring into
 * feature:onboarding's auth success path, which would pull the Firebase Messaging dependency
 * into a feature module — deferred). A token still gets registered on the *next* app launch,
 * or immediately if Firebase happens to (re)issue a token around that time via `onNewToken`.
 */
@HiltViewModel
class PushTokenRegistrarViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val deviceTokenRepository: DeviceTokenRepository,
) : ViewModel() {
    init {
        val userId = authRepository.currentUserId
        if (userId != null) {
            viewModelScope.launch {
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

@Composable
fun PushTokenRegistrar(viewModel: PushTokenRegistrarViewModel = hiltViewModel()) {
    // No UI — the ViewModel's init block does the work. Composing this once (see MainActivity)
    // is enough to create/retain it for the process lifetime.
}
