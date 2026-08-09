package com.riskdetectedan.app.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.riskdetectedan.app.MainActivity
import com.riskdetectedan.app.R
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.data.auth.AuthRepository
import com.riskdetectedan.core.data.notifications.DeviceTokenRepository
import com.riskdetectedan.core.data.release.AndroidRuntimeGateName
import com.riskdetectedan.core.data.release.ReleasePolicyRepository
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
 * `onMessageReceived` applies the Android notifications runtime gate, validates the typed
 * identifier-only route payload and renders a local notification with a PendingIntent back into
 * MainActivity. Background/killed delivery uses the same extras parser when Android launches the
 * activity from FCM's system notification.
 */
@AndroidEntryPoint
class RdFirebaseMessagingService : FirebaseMessagingService() {

    @Inject lateinit var deviceTokenRepository: DeviceTokenRepository

    @Inject lateinit var authRepository: AuthRepository

    @Inject lateinit var environmentConfig: RdEnvironmentConfig

    @Inject lateinit var releasePolicyRepository: ReleasePolicyRepository

    @Inject lateinit var notificationDeepLinkHandler: NotificationDeepLinkHandler

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        if (environmentConfig.firebaseProjectId.isBlank()) return
        val userId = authRepository.currentUserId ?: return
        scope.launch {
            if (!releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Notifications).enabled) return@launch
            val notificationsEnabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(
                    this@RdFirebaseMessagingService,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
            deviceTokenRepository.registerToken(userId, token, notificationsEnabled = notificationsEnabled)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        scope.launch {
            if (!releasePolicyRepository.resolveGate(AndroidRuntimeGateName.Notifications).enabled) return@launch
            showForegroundNotification(message)
        }
    }

    private fun showForegroundNotification(message: RemoteMessage) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val payload = NotificationDeepLinkParser.parse(message.data) ?: return
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(RdR.string.rd_bildirim_kanali),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        notificationDeepLinkHandler.putIntoIntent(message, intent)
        val pendingIntent = PendingIntent.getActivity(
            this,
            payload.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(message.notification?.title ?: getString(RdR.string.rd_app_name))
            .setContentText(message.notification?.body ?: getString(RdR.string.rd_yeni_guncelleme_var))
            .setStyle(NotificationCompat.BigTextStyle().bigText(message.notification?.body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(this).notify(payload.hashCode(), notification)
    }

    private companion object {
        const val CHANNEL_ID = "riskdetected_updates"
    }
}
