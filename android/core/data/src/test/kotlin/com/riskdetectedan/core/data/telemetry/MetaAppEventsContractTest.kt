package com.riskdetectedan.core.data.telemetry

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class MetaAppEventsContractTest {
    @Test
    fun businessEventsAreDeduplicatedAcrossRelaunchAndNeverExposeSourceIds() {
        val context = RuntimeEnvironment.getApplication().applicationContext
        val preferences = context.getSharedPreferences("meta-${UUID.randomUUID()}", Context.MODE_PRIVATE)
        val events = mutableListOf<MetaEventEmission>()
        val sourceId = UUID.randomUUID().toString()
        val sink = MetaEventSink(events::add)

        MetaEventEmitter(MetaEventLedger(preferences)).apply {
            emit(sink, "risk_assessment_completed", sourceId)
            emit(sink, "risk_assessment_completed", sourceId)
            emit(sink, "report_created", sourceId, parameters = mapOf("format" to "pdf"))
        }
        MetaEventEmitter(MetaEventLedger(preferences)).emit(
            sink,
            "report_created",
            sourceId,
            parameters = mapOf("format" to "pdf"),
        )

        assertEquals(listOf("risk_assessment_completed", "report_created"), events.map { it.name })
        assertEquals(mapOf("format" to "pdf"), events.last().parameters)
        assertFalse(events.toString().contains(sourceId))
    }

    @Test
    fun trialAndSubscriptionHaveStandardPairsWithoutDoubleRevenue() {
        val context = RuntimeEnvironment.getApplication().applicationContext
        val preferences = context.getSharedPreferences("meta-${UUID.randomUUID()}", Context.MODE_PRIVATE)
        val events = mutableListOf<MetaEventEmission>()
        val sink = MetaEventSink(events::add)
        val emitter = MetaEventEmitter(MetaEventLedger(preferences))
        val parameters = mapOf("fb_content_id" to "riskdetected_plus_monthly", "fb_currency" to "TRY")

        emitter.emit(sink, "trial_started", "trial", "StartTrial", parameters, 0.0)
        emitter.emit(sink, "subscription_started", "paid", "Subscribe", parameters, 249.99)
        emitter.emit(sink, "subscription_started", "paid", "Subscribe", parameters, 249.99)

        assertEquals(
            listOf("trial_started", "StartTrial", "subscription_started", "Subscribe"),
            events.map { it.name },
        )
        assertNull(events[0].valueToSum)
        assertEquals(0.0, events[1].valueToSum)
        assertNull(events[2].valueToSum)
        assertEquals(249.99, events[3].valueToSum)
    }

    @Test
    fun registrationPolicyRejectsExistingAccountsAndAcceptsFreshSignups() {
        val now = 1_800_000L
        assertFalse(MetaRegistrationPolicy.isNewRegistration(0L, now, now))
        assertFalse(MetaRegistrationPolicy.isNewRegistration(now - 5_000L, null, now))
        assertFalse(MetaRegistrationPolicy.isNewRegistration(now + 1L, now, now))
        assertTrue(MetaRegistrationPolicy.isNewRegistration(now - 5_000L, now - 4_000L, now))
    }
}
