package com.riskdetectedan.app.push

import android.content.Intent
import androidx.lifecycle.ViewModel
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

enum class NotificationRouteTarget {
    Home,
    Analyses,
    Reports,
    Profile,
    NewAnalysis,
}
data class NotificationDeepLinkPayload(
    val type: String,
    val target: NotificationRouteTarget,
    val analysisId: String? = null,
    val reportId: String? = null,
)

object NotificationDeepLinkParser {
    private val uuid = Regex(
        "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        RegexOption.IGNORE_CASE,
    )

    fun parse(data: Map<String, String>): NotificationDeepLinkPayload? {
        val type = data["type"]?.trim()?.lowercase() ?: return null
        val analysisId = data["analysis_id"]?.takeIf(uuid::matches)
        val reportId = data["report_id"]?.takeIf(uuid::matches)
        val target = when (type) {
            "analysis_complete" -> NotificationRouteTarget.Analyses
            "report_ready" -> NotificationRouteTarget.Reports
            "account_updates", "trial_reminder", "progress_weekly_summary",
            "progress_monthly_summary", "progress_milestones" -> NotificationRouteTarget.Profile
            "first_analysis_reminder", "inactivity_reminder", "manual_app_reminder" ->
                NotificationRouteTarget.NewAnalysis
            else -> return null
        }
        if (target == NotificationRouteTarget.Analyses && analysisId == null) return null
        if (target == NotificationRouteTarget.Reports && reportId == null) return null
        return NotificationDeepLinkPayload(type, target, analysisId, reportId)
    }
}

@Singleton
class PendingNotificationRouteStore @Inject constructor() {
    private val _pending = MutableStateFlow<NotificationDeepLinkPayload?>(null)
    val pending: StateFlow<NotificationDeepLinkPayload?> = _pending.asStateFlow()

    fun accept(data: Map<String, String>) {
        NotificationDeepLinkParser.parse(data)?.let { _pending.value = it }
    }

    fun consume() {
        _pending.value = null
    }
}

@Singleton
class NotificationDeepLinkHandler @Inject constructor(
    private val store: PendingNotificationRouteStore,
) {
    fun handle(intent: Intent) {
        val extras = intent.extras ?: return
        val data = buildMap {
            for (key in listOf("type", "analysis_id", "report_id")) {
                extras.getString(key)?.let { put(key, it) }
            }
        }
        store.accept(data)
    }

    fun putIntoIntent(message: RemoteMessage, intent: Intent) {
        for (key in listOf("type", "analysis_id", "report_id")) {
            message.data[key]?.let { intent.putExtra(key, it) }
        }
    }
}

@HiltViewModel
class NotificationRouteViewModel @Inject constructor(
    private val store: PendingNotificationRouteStore,
) : ViewModel() {
    val pending: StateFlow<NotificationDeepLinkPayload?> = store.pending

    fun consume() = store.consume()
}
