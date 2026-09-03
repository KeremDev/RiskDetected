package com.riskdetectedan.app.push

import android.content.Context
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationManagerCompat
import com.riskdetectedan.core.designsystem.R as RdR

/**
 * One notification channel for the whole app, created before any notification can arrive.
 *
 * Android renders an FCM message itself whenever the app is backgrounded or killed, and it puts
 * that notification on the channel named by the manifest's `default_notification_channel_id`.
 * Without that entry those notifications landed on FCM's own fallback channel ("Miscellaneous")
 * while foreground notifications used `riskdetected_updates` — the same app then showed the user
 * two unrelated switches in system settings, and turning off the branded one silenced nothing.
 *
 * [ID] is deliberately not a string resource: the English resource generator demands a
 * translation for every entry in `values/strings.xml`, and a channel id is an identifier, not
 * copy. NotificationBrandingTest asserts the manifest and this constant still agree. iOS has no
 * equivalent because APNs alerts carry no channel.
 */
object RdNotificationChannel {

    const val ID = "riskdetected_updates"

    /** Idempotent — re-creating an existing channel only updates its name, never the importance
     * or any per-channel choice the user has since made. */
    fun ensure(context: Context) {
        NotificationManagerCompat.from(context).createNotificationChannel(
            NotificationChannelCompat.Builder(ID, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                .setName(context.getString(RdR.string.rd_bildirim_kanali))
                .build(),
        )
    }
}
