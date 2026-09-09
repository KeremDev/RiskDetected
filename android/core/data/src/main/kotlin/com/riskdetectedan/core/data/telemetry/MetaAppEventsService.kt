package com.riskdetectedan.core.data.telemetry

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import com.facebook.FacebookSdk
import com.facebook.appevents.AppEventsConstants
import com.facebook.appevents.AppEventsLogger
import com.riskdetectedan.core.common.RdEnvironment
import com.riskdetectedan.core.common.RdEnvironmentConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.abs

internal data class MetaEventEmission(
    val name: String,
    val parameters: Map<String, String> = emptyMap(),
    val valueToSum: Double? = null,
)

internal fun interface MetaEventSink {
    fun log(event: MetaEventEmission)
}

/**
 * Persistent local idempotency. The source value is hashed before storage and is never included
 * in an App Event payload. This mirrors iOS's MetaEventLedger contract exactly.
 */
internal class MetaEventLedger(private val preferences: SharedPreferences) {
    private val lock = Any()

    fun claim(event: String, sourceId: String): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$event:$sourceId".toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
        val key = "rd.meta.sent.v1.$digest"
        return synchronized(lock) {
            if (preferences.getBoolean(key, false)) {
                false
            } else {
                preferences.edit().putBoolean(key, true).commit()
            }
        }
    }
}

internal object MetaRegistrationPolicy {
    fun isNewRegistration(
        createdAtMillis: Long,
        lastSignInAtMillis: Long?,
        nowMillis: Long,
    ): Boolean {
        val lastSignIn = lastSignInAtMillis ?: return false
        val accountAge = nowMillis - createdAtMillis
        return abs(lastSignIn - createdAtMillis) < 60_000L && accountAge in 0L..<600_000L
    }
}

/** Fixed-name event emitter shared by production and contract tests. */
internal class MetaEventEmitter(private val ledger: MetaEventLedger) {
    fun emit(
        sink: MetaEventSink,
        customName: String,
        sourceId: String,
        standardName: String? = null,
        parameters: Map<String, String> = emptyMap(),
        standardValue: Double? = null,
    ) {
        if (sourceId.isBlank() || !ledger.claim(customName, sourceId)) return
        sink.log(MetaEventEmission(name = customName, parameters = parameters))
        standardName?.let { standard ->
            sink.log(
                MetaEventEmission(
                    name = standard,
                    parameters = parameters,
                    valueToSum = standardValue,
                ),
            )
        }
    }
}

/**
 * Meta App Events parity layer for Android.
 *
 * It deliberately does not request or collect Google Advertising ID, set a Meta user ID, send
 * user matching data, or forward photos/analysis/report content. Delivery is always best effort
 * and no product operation waits for Meta.
 */
@Singleton
class MetaAppEventsService @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
    private val environment: RdEnvironmentConfig,
) {
    private val emitter = MetaEventEmitter(
        MetaEventLedger(context.getSharedPreferences("rd_meta_app_events", Context.MODE_PRIVATE)),
    )
    private val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.IO + CoroutineExceptionHandler { _, _ ->
            // Marketing telemetry must never crash or block an auth/product flow.
        },
    )
    @Volatile private var configured = false
    @Volatile private var logger: AppEventsLogger? = null

    fun configure(application: Application) {
        if (configured || environment.environment != RdEnvironment.Production) return
        runCatching {
            enforceLimitedDataUse(application)
            logger = AppEventsLogger.newLogger(application)
            configured = true

            // Auto app-event logging is disabled in the manifest, so activation is explicit.
            AppEventsLogger.activateApp(application)
            emit(customName = "first_launch", sourceId = "installation")
            observeRegistrations()
        }.onFailure {
            configured = false
            logger = null
        }
    }

    fun analysisCompleted(analysisId: String) {
        emit(customName = "risk_assessment_completed", sourceId = analysisId)
    }

    fun firstAnalysis(userId: String) {
        emit(customName = "first_risk_analysis", sourceId = userId)
    }

    fun reportCreated(reportId: String, format: String) {
        val normalizedFormat = format.lowercase().takeIf { it == "pdf" || it == "xlsx" } ?: return
        emit(
            customName = "report_created",
            sourceId = reportId,
            parameters = mapOf("format" to normalizedFormat),
        )
    }

    fun purchase(
        transactionId: String,
        productId: String,
        isTrial: Boolean,
        price: Double?,
        currency: String?,
    ) {
        if (transactionId.isBlank() || productId.isBlank()) return
        val parameters = buildMap {
            put(AppEventsConstants.EVENT_PARAM_CONTENT_ID, productId)
            currency?.trim()?.takeIf { it.isNotEmpty() }?.let {
                put(AppEventsConstants.EVENT_PARAM_CURRENCY, it.uppercase())
            }
        }
        emit(
            customName = if (isTrial) "trial_started" else "subscription_started",
            sourceId = transactionId,
            standardName = if (isTrial) {
                AppEventsConstants.EVENT_NAME_START_TRIAL
            } else {
                AppEventsConstants.EVENT_NAME_SUBSCRIBE
            },
            parameters = parameters,
            standardValue = if (isTrial) 0.0 else price?.takeIf { it >= 0.0 },
        )
    }

    private fun observeRegistrations() {
        scope.launch {
            client.auth.sessionStatus.collectLatest { status ->
                val user = (status as? SessionStatus.Authenticated)?.session?.user ?: return@collectLatest
                val createdAtMillis = user.createdAt?.toEpochMilliseconds() ?: return@collectLatest
                val lastSignInAtMillis = user.lastSignInAt?.toEpochMilliseconds()
                if (
                    MetaRegistrationPolicy.isNewRegistration(
                        createdAtMillis = createdAtMillis,
                        lastSignInAtMillis = lastSignInAtMillis,
                        nowMillis = System.currentTimeMillis(),
                    )
                ) {
                    emit(
                        customName = "registration_completed",
                        sourceId = user.id,
                        standardName = AppEventsConstants.EVENT_NAME_COMPLETED_REGISTRATION,
                    )
                }
            }
        }
    }

    private fun emit(
        customName: String,
        sourceId: String,
        standardName: String? = null,
        parameters: Map<String, String> = emptyMap(),
        standardValue: Double? = null,
    ) {
        if (!configured || environment.environment != RdEnvironment.Production) return
        val appEventsLogger = logger ?: return
        runCatching {
            enforceLimitedDataUse(null)
            emitter.emit(
                sink = MetaEventSink { event ->
                    val bundle = Bundle().apply {
                        event.parameters.forEach { (key, value) -> putString(key, value) }
                    }
                    if (event.valueToSum != null) {
                        appEventsLogger.logEvent(event.name, event.valueToSum, bundle)
                    } else {
                        appEventsLogger.logEvent(event.name, bundle)
                    }
                },
                customName = customName,
                sourceId = sourceId,
                standardName = standardName,
                parameters = parameters,
                standardValue = standardValue,
            )
        }
    }

    private fun enforceLimitedDataUse(context: Context?) {
        FacebookSdk.setAutoLogAppEventsEnabled(false)
        FacebookSdk.setAdvertiserIDCollectionEnabled(false)
        context?.let { FacebookSdk.setLimitEventAndDataUsage(it, true) }
        AppEventsLogger.clearUserID()
        AppEventsLogger.clearUserData()
    }
}
