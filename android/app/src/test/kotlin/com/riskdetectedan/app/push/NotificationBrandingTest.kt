package com.riskdetectedan.app.push

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.test.core.app.ApplicationProvider
import com.riskdetectedan.app.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NotificationBrandingTest {

    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test
    fun `foreground notification uses dedicated status mark and full brand artwork`() {
        val pendingIntent = PendingIntent.getActivity(
            context,
            17,
            Intent("com.riskdetectedan.TEST_NOTIFICATION"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = createRiskDetectedNotification(
            context = context,
            channelId = "test",
            pendingIntent = pendingIntent,
            title = "Rapor hazır",
            body = "Risk raporun oluşturuldu.",
        )

        assertEquals(R.drawable.ic_launcher_monochrome, notification.smallIcon.resId)
        assertNotNull(notification.getLargeIcon())
        assertEquals(context.getColor(R.color.rd_notification_accent), notification.color)
        assertEquals("Rapor hazır", notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Risk raporun oluşturuldu.", notification.extras.getString(Notification.EXTRA_TEXT))
        assertEquals(NotificationCompat.CATEGORY_STATUS, notification.category)
    }

    @Test
    fun `background FCM notifications use the same dedicated status mark`() {
        val applicationInfo = context.packageManager.getApplicationInfo(
            context.packageName,
            PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
        )

        assertEquals(
            R.drawable.ic_launcher_monochrome,
            applicationInfo.metaData.getInt("com.google.firebase.messaging.default_notification_icon"),
        )
        assertEquals(
            R.color.rd_notification_accent,
            applicationInfo.metaData.getInt("com.google.firebase.messaging.default_notification_color"),
        )
    }

    /** Background/killed-state messages are rendered by FCM on the channel this meta-data names.
     * Without the declaration they landed on FCM's fallback channel while foreground
     * notifications used ours — one app, two switches in system settings. */
    @Test
    fun `background and foreground notifications share one declared channel`() {
        val applicationInfo = context.packageManager.getApplicationInfo(
            context.packageName,
            PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
        )
        val declaredChannelId = applicationInfo.metaData
            .getString("com.google.firebase.messaging.default_notification_channel_id")

        assertEquals(RdNotificationChannel.ID, declaredChannelId)

        RdNotificationChannel.ensure(context)
        val channel = NotificationManagerCompat.from(context)
            .getNotificationChannelCompat(RdNotificationChannel.ID)

        assertNotNull(channel)
        assertEquals(declaredChannelId, channel!!.id)
    }
}
