package com.riskdetectedan.app.push

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationManagerCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewModelScope
import com.google.firebase.messaging.FirebaseMessaging
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.notifications.DeviceTokenRepository
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
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
    private val environmentConfig: RdEnvironmentConfig,
    private val releasePolicyRepository: ReleasePolicyRepository,
    @ApplicationContext private val context: Context,
) : ViewModel() {
    init {
        viewModelScope.launch {
            authRepository.currentUserIdFlow.collectLatest { userId ->
                if (userId != null) registerCurrentToken(userId)
            }
        }
    }

    fun refresh() {
        val userId = authRepository.currentUserId ?: return
        viewModelScope.launch { registerCurrentToken(userId) }
    }

    private suspend fun registerCurrentToken(userId: String) {
        if (environmentConfig.firebaseProjectId.isBlank()) return
        if (!releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Notifications).enabled) return
        val token = try {
            FirebaseMessaging.getInstance().token.await()
        } catch (t: Throwable) {
            null
        } ?: return
        val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED)
        deviceTokenRepository.registerToken(userId, token, notificationsEnabled = notificationsEnabled)
    }
}

@Composable
fun PushTokenRegistrar(viewModel: PushTokenRegistrarViewModel = hiltViewModel()) {
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) viewModel.refresh()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
}
