package com.riskdetectedan.core.data.telemetry

import android.content.Context
import com.riskdetectedan.core.common.RdEnvironmentConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** First party only. No free-form metadata, exception message, URI or image ever enters this queue. */
@Serializable
internal data class FlowEvent(
    val client_event_id: String = UUID.randomUUID().toString(),
    val user_id: String, val session_id: String, val platform: String = "android",
    val app_version: String, val app_build: String,
    val stage: String, val outcome: String, val reason: String, val photo_count: Int,
    val client_occurred_at: String = Instant.now().toString(),
)

@Singleton
class ClientFlowEvents @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
    private val environment: RdEnvironmentConfig,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineExceptionHandler { _, _ ->
        // A diagnostics transport/storage failure must never crash the product flow.
    })
    private val prefs = context.getSharedPreferences("rd_client_flow_events", Context.MODE_PRIVATE)
    private val session = UUID.randomUUID().toString()
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }
    private val lock = Any()
    private var flushing = false

    init { scope.launch { client.auth.sessionStatus.collect { flush() } } }

    fun record(stage: String, outcome: String, reason: String = "none", photoCount: Int = 0) {
        try {
        if (stage !in stages || outcome !in outcomes || reason !in reasons) return
        val owner = client.auth.currentUserOrNull()?.id ?: return
        val event = FlowEvent(user_id = owner, session_id = session,
            app_version = environment.appVersionName.take(32), app_build = environment.appVersionCode.toString(),
            stage = stage, outcome = outcome, reason = reason, photo_count = photoCount.coerceIn(0, 3))
        synchronized(lock) { save((read() + event).takeLast(200)) }
        flush()
        } catch (_: Exception) {
            // Best effort: unavailable local diagnostics storage is not a checkout/analysis error.
        }
    }

    private fun read(): List<FlowEvent> = runCatching {
        json.decodeFromString<List<FlowEvent>>(prefs.getString("queue", "[]")!!)
            .filter { Instant.parse(it.client_occurred_at).isAfter(Instant.now().minusSeconds(86400)) }
    }.getOrDefault(emptyList())
    private fun save(events: List<FlowEvent>) { prefs.edit().putString("queue", json.encodeToString(events)).apply() }

    private fun flush() {
        synchronized(lock) { if (flushing) return; save(read()); flushing = true }
        scope.launch {
            try {
                var failures = 0
                while (isActive) {
                    val next = synchronized(lock) { read().firstOrNull { it.user_id == client.auth.currentUserOrNull()?.id } } ?: break
                    try {
                        withTimeout(15_000) {
                            client.postgrest.from("client_flow_events").upsert(next) {
                                onConflict = "client_event_id"; ignoreDuplicates = true
                            }
                        }
                        synchronized(lock) { save(read().filterNot { it.client_event_id == next.client_event_id }) }
                        failures = 0
                    } catch (e: Exception) {
                        if (e is CancellationException && e !is TimeoutCancellationException) throw e
                        if (++failures >= 3) break
                        delay(5_000L * failures)
                    }
                }
            } finally { synchronized(lock) { flushing = false } }
        }
    }

    companion object {
        val stages = setOf("home", "photo_picker", "photo_import", "photo_ready", "analysis_cta", "analysis_validation", "analysis_prepare", "analysis_create", "analysis_upload", "analysis_submit", "analysis_result", "billing_launch", "billing_result")
        val outcomes = setOf("started", "completed", "cancelled", "blocked", "failed", "pending")
        val reasons = setOf("none", "unknown", "auth", "quota", "safety_profile", "photo_limit", "no_photo", "permission", "io", "network", "timeout", "runtime_gate", "membership", "activity_inactive", "already_running", "store", "backend")
    }
}
