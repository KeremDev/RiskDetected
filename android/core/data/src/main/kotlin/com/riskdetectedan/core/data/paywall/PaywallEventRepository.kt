package com.riskdetectedan.core.data.paywall

import com.riskdetectedan.core.data.profile.SubscriptionTier
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors PaywallEventService.swift's `record()` — analytics only, never blocks/affects the
 * purchase flow (errors are swallowed, matching the Swift `Task { try? ... }` fire-and-forget).
 *
 * Only the 5 event names Android's simpler single-layout paywall (feature #20) actually has a
 * real moment for are ported: `view`/`purchase_started`/`purchase_succeeded`/`purchase_failed`/
 * `restore_tap`. `close`/`cta_tap`/`plan_select`/`billing_select` aren't ported — Android's
 * `PaywallScreen` has no distinct "select a plan, then confirm" step or a dismiss action
 * separate from the system back gesture, so those Swift interaction moments don't exist here to
 * instrument (not a silent drop, there is genuinely no click to attach the event to).
 * `payment_pending`/`personal_plan_view`/`personal_plan_continue`/`trial_invite_*` exist as Swift
 * enum cases but AREN'T in `paywall_events_event_name_check`'s allowed list either (pre-existing
 * drift between the Swift enum and the DB constraint, not something this port needs to fix) —
 * skipped for that reason too, sending them would just fail the CHECK.
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

enum class PaywallEventName(val wireValue: String) {
    View("view"),
    PurchaseStarted("purchase_started"),
    PurchaseSucceeded("purchase_succeeded"),
    PurchaseFailed("purchase_failed"),
    RestoreTap("restore_tap"),
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
    @SerialName("user_id") val userId: String,
    @SerialName("funnel_session_id") val funnelSessionId: String,
    val source: String,
    @SerialName("variant_id") val variantId: String,
    @SerialName("segment_key") val segmentKey: String? = null,
    @SerialName("event_name") val eventName: String,
    @SerialName("selected_tier") val selectedTier: SubscriptionTier? = null,
    val billing: String? = null,
    @SerialName("product_identifier") val productIdentifier: String? = null,
    val metadata: PaywallEventMetadata,
)

@Singleton
class PaywallEventRepository @Inject constructor(private val client: SupabaseClient) {
    suspend fun record(
        event: PaywallEventName,
        userId: String,
        funnelSessionId: String,
        selectedTier: SubscriptionTier?,
        billing: String?,
        productIdentifier: String?,
        metadata: PaywallEventMetadata,
        source: String = SOURCE,
    ) {
        try {
            client.postgrest.from("paywall_events").insert(
                PaywallEventPayload(
                    userId = userId,
                    funnelSessionId = funnelSessionId,
                    source = source,
                    variantId = VARIANT_ID,
                    eventName = event.wireValue,
                    selectedTier = selectedTier,
                    billing = billing,
                    productIdentifier = productIdentifier,
                    metadata = metadata,
                ),
            )
        } catch (t: Throwable) {
            // Analytics must never surface an error to the purchase flow — same as iOS's
            // fire-and-forget Task{} + logger-only error handling.
        }
    }
}
