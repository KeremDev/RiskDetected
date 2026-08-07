package com.riskdetectedan.app.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.notifications.DeviceTokenRepository
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Registers a fresh FCM token when Firebase issues one (fresh install, token rotation, app data
 * cleared) — this is the Android counterpart to `didRegisterForRemoteNotifications` in
 * NotificationService.swift, except FCM tokens don't arrive per-launch like APNs device tokens
 * do; they arrive here only when genuinely new. [com.riskdetectedan.app.push.PushTokenRegistrar]
 * covers the other case (an already-issued token on a fresh app launch for an already
 * signed-in user).
 *
 * `onMessageReceived` doesn't do anything with the payload yet — the backend's FCM *sending*
 * path (`send-push-notification`'s `providers/fcm.ts`) is still Faz 7 scope, not built this
 * session (only the APNs path exists in production today, per this session's earlier findings).
 * This override exists so a manually-sent Firebase Console "Test message" can be verified to
 * arrive at all — logged, not silently dropped — without pretending real production push
 * delivery to Android already works end to end.
 */
@AndroidEntryPoint
class RdFirebaseMessagingService : FirebaseMessagingService() {

    @Inject lateinit var deviceTokenRepository: DeviceTokenRepository

    @Inject lateinit var authRepository: AuthRepository

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        val userId = authRepository.currentUserId ?: return
        scope.launch {
            deviceTokenRepository.registerToken(userId, token, notificationsEnabled = true)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        android.util.Log.d("RdFirebaseMessagingService", "FCM message received: ${message.data}")
    }
}
