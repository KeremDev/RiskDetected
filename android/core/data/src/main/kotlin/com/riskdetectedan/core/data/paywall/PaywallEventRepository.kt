package com.riskdetectedan.core.data.paywall

import android.content.Context
import android.util.Log
import com.riskdetectedan.core.data.profile.SubscriptionTier
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors PaywallEventService.swift's durable delivery contract. Events are persisted before
 * upload, retried outside the paywall ViewModel lifecycle, and acknowledged only after PostgREST
 * accepts them. `client_event_id` makes a retry safe after a lost HTTP response.
 *
 * Android now mirrors the live in-app paywall interactions, including explicit plan/billing
 * selection, CTA, close, cancellation and payment-pending events. The shared database constraint
 * is maintained by the paywall delivery-integrity migration and is covered by pgTAP.
 *
 * `source` is `"in_app"` for Profile → "Planı yükselt" (feature #20) and `"onboarding_v2"` for
 * the onboarding-step-11 paywall (feature:onboarding's `OBTimelinePaywallScreen`, wired to real
 * purchases once Android caught up to iOS's live onboarding pricing) — both values are already
 * allowed by `paywall_events_source_check`. `variant_id` is `"android_default_v1"` — a real, honest label
 * for "the one layout Android has," not a fabricated A/B-test variant; Android has no paywall
 * variant-testing infrastructure the way iOS's `PaywallSource`/segment system does, so
 * `segment_key` is always null rather than guessing at a sector segment.
 */
private const val SOURCE = "in_app"
private const val VARIANT_ID = "android_default_v1"
private const val TAG = "PaywallEvents"

enum class PaywallEventName(val wireValue: String) {
    EntryTap("entry_tap"),
    View("view"),
    Close("close"),
    CtaTap("cta_tap"),
    PlanSelect("plan_select"),
    BillingSelect("billing_select"),
    PurchaseStarted("purchase_started"),
    PurchaseSucceeded("purchase_succeeded"),
    PurchaseFailed("purchase_failed"),
    PurchaseCancelled("purchase_cancelled"),
    PaymentPending("payment_pending"),
    RestoreTap("restore_tap"),
}

@Serializable
data class PaywallEntryAttribution(
    @SerialName("entry_point") val entryPoint: String,
    @SerialName("entry_surface") val entrySurface: String,
    @SerialName("entry_component") val entryComponent: String,
    @SerialName("entry_target_tier") val entryTargetTier: SubscriptionTier? = null,
    @SerialName("analysis_id") val analysisId: String? = null,
    @SerialName("result_section") val resultSection: String? = null,
    @SerialName("item_id") val itemId: String? = null,
    val attributes: Map<String, String> = emptyMap(),
    @SerialName("client_occurred_at") val clientOccurredAt: String = Instant.now().toString(),
)

internal fun PaywallEntryAttribution.toEntryContext(funnelSessionId: String): JsonObject = buildJsonObject {
    put("funnel_session_id", funnelSessionId)
    put("entry_point", entryPoint)
    put("surface", entrySurface)
    put("component", entryComponent)
    entryTargetTier?.let { put("target_tier", it.name.lowercase()) }
    analysisId?.let { put("analysis_id", it) }
    resultSection?.let { put("result_section", it) }
    itemId?.let { put("item_id", it) }
    putJsonObject("attributes") {
        attributes.forEach { (key, value) -> put(key, value) }
    }
    put("client_occurred_at", clientOccurredAt)
}

@Serializable
data class PaywallEventMetadata(
    val layout: String = "android_default",
    @SerialName("current_tier") val currentTier: String,
    @SerialName("selected_package_id") val selectedPackageId: String? = null,
    @SerialName("notice_present") val noticePresent: Boolean = false,
    @SerialName("error_message") val errorMessage: String? = null,
    @SerialName("context_headline") val contextHeadline: String? = null,
    @SerialName("purchase_error") val purchaseError: String? = null,
)

@Serializable
private data class PaywallEventPayload(
    @SerialName("client_event_id") val clientEventId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("funnel_session_id") val funnelSessionId: String,
    val source: String,
    @SerialName("variant_id") val variantId: String,
    @SerialName("segment_key") val segmentKey: String? = null,
    @SerialName("event_name") val eventName: String,
    @SerialName("selected_tier") val selectedTier: SubscriptionTier? = null,
    val billing: String? = null,
    @SerialName("product_identifier") val productIdentifier: String? = null,
    @SerialName("client_occurred_at") val clientOccurredAt: String,
    @SerialName("app_session_id") val appSessionId: String,
    @SerialName("entry_point") val entryPoint: String? = null,
    @SerialName("entry_surface") val entrySurface: String? = null,
    @SerialName("entry_component") val entryComponent: String? = null,
    @SerialName("entry_target_tier") val entryTargetTier: SubscriptionTier? = null,
    @SerialName("analysis_id") val analysisId: String? = null,
    @SerialName("result_section") val resultSection: String? = null,
    @SerialName("item_id") val itemId: String? = null,
    @SerialName("entry_context") val entryContext: JsonObject = buildJsonObject {},
    val metadata: PaywallEventMetadata,
)

@Singleton
class PaywallEventRepository @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
) {
    private val appSessionId = UUID.randomUUID().toString()
    private val deliveryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val queueLock = Any()
    private val isFlushing = AtomicBoolean(false)
    private val retryAttempt = AtomicInteger(0)
    @Volatile private var retryJob: Job? = null

    fun record(
        event: PaywallEventName,
        userId: String,
        funnelSessionId: String,
        selectedTier: SubscriptionTier?,
        billing: String?,
        productIdentifier: String?,
        metadata: PaywallEventMetadata,
        source: String = SOURCE,
        attribution: PaywallEntryAttribution? = null,
    ) {
        val clientOccurredAt = Instant.now().toString()
        val payload = PaywallEventPayload(
            clientEventId = UUID.randomUUID().toString(),
            userId = userId,
            funnelSessionId = funnelSessionId,
            source = source,
            variantId = VARIANT_ID,
            eventName = event.wireValue,
            selectedTier = selectedTier,
            billing = billing,
            productIdentifier = productIdentifier,
            clientOccurredAt = clientOccurredAt,
            appSessionId = appSessionId,
            entryPoint = attribution?.entryPoint,
            entrySurface = attribution?.entrySurface,
            entryComponent = attribution?.entryComponent,
            entryTargetTier = attribution?.entryTargetTier,
            analysisId = attribution?.analysisId,
            resultSection = attribution?.resultSection,
            itemId = attribution?.itemId,
            entryContext = attribution?.toEntryContext(funnelSessionId) ?: buildJsonObject {},
            metadata = metadata,
        )
        enqueue(payload)
        flushPending()
    }

    /** May be called from application/activity lifecycle hooks after auth or connectivity returns. */
    fun flushPending() {
        retryJob?.cancel()
        retryJob = null
        if (!isFlushing.compareAndSet(false, true)) return
        deliveryScope.launch {
            var deliveryFailed = false
            try {
                while (true) {
                    val next = synchronized(queueLock) { readPendingLocked().firstOrNull() } ?: break
                    try {
                        client.postgrest.from("paywall_events").upsert(next) {
                            onConflict = "client_event_id"
                            ignoreDuplicates = true
                        }
                        acknowledge(next.clientEventId)
                    } catch (t: Throwable) {
                        deliveryFailed = true
                        Log.e(TAG, "Paywall event delivery deferred: ${next.eventName}", t)
                        break
                    }
                }
            } finally {
                isFlushing.set(false)
                // Close the small race where a new event is enqueued after the loop observed an
                // empty queue but before the flag was cleared. Network failures use a bounded
                // exponential retry so delivery also recovers while the app stays foregrounded.
                if (deliveryFailed) {
                    scheduleRetry()
                } else if (synchronized(queueLock) { readPendingLocked().isNotEmpty() }) {
                    flushPending()
                } else {
                    retryAttempt.set(0)
                }
            }
        }
    }

    private fun scheduleRetry() {
        if (synchronized(queueLock) { readPendingLocked().isEmpty() }) return
        val attempt = retryAttempt.getAndUpdate { current -> (current + 1).coerceAtMost(6) }
        val delayMillis = (5_000L * (1L shl attempt.coerceAtMost(6))).coerceAtMost(300_000L)
        retryJob?.cancel()
        retryJob = deliveryScope.launch {
            delay(delayMillis)
            retryJob = null
            flushPending()
        }
    }

    private fun enqueue(payload: PaywallEventPayload) = synchronized(queueLock) {
        val pending = readPendingLocked()
        if (pending.any { it.clientEventId == payload.clientEventId }) return@synchronized
        persistLocked(pending + payload)
    }

    private fun acknowledge(clientEventId: String) = synchronized(queueLock) {
        persistLocked(readPendingLocked().filterNot { it.clientEventId == clientEventId })
    }

    private fun readPendingLocked(): List<PaywallEventPayload> {
        val encoded = preferences.getString(PENDING_EVENTS_KEY, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<PaywallEventPayload>>(encoded) }
            .onFailure {
                Log.e(TAG, "Pending paywall event queue could not be decoded", it)
                preferences.edit().remove(PENDING_EVENTS_KEY).commit()
            }
            .getOrDefault(emptyList())
    }

    private fun persistLocked(events: List<PaywallEventPayload>) {
        val editor = preferences.edit()
        if (events.isEmpty()) editor.remove(PENDING_EVENTS_KEY)
        else editor.putString(PENDING_EVENTS_KEY, json.encodeToString(events))
        if (!editor.commit()) Log.e(TAG, "Pending paywall event queue could not be persisted")
    }

    private companion object {
        const val PREFERENCES_NAME = "rd_paywall_event_delivery"
        const val PENDING_EVENTS_KEY = "pending_events_v1"
    }
}
