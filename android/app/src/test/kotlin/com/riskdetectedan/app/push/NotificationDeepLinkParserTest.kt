package com.riskdetectedan.app.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationDeepLinkParserTest {
    @Test
    fun `analysis notification requires a UUID and routes to analyses`() {
        val payload = NotificationDeepLinkParser.parse(
            mapOf(
                "type" to "analysis_complete",
                "analysis_id" to "123e4567-e89b-42d3-a456-426614174000",
            ),
        )
        assertEquals(NotificationRouteTarget.Analyses, payload?.target)
        assertNull(NotificationDeepLinkParser.parse(mapOf("type" to "analysis_complete")))
    }

    @Test
    fun `unknown type and malformed identifiers fail closed`() {
        assertNull(NotificationDeepLinkParser.parse(mapOf("type" to "unknown")))
        assertNull(
            NotificationDeepLinkParser.parse(
                mapOf("type" to "report_ready", "report_id" to "not-an-id"),
            ),
        )
    }

    @Test
    fun `account update routes to profile without a record identifier`() {
        val payload = NotificationDeepLinkParser.parse(mapOf("type" to "account_updates"))

        assertEquals(NotificationRouteTarget.Profile, payload?.target)
    }

    @Test
    fun `valid event id is retained for open tracking and malformed value is discarded`() {
        val eventId = "123e4567-e89b-42d3-a456-426614174000"
        val valid = NotificationDeepLinkParser.parse(
            mapOf("type" to "first_analysis_reminder", "event_id" to eventId),
        )
        val malformed = NotificationDeepLinkParser.parse(
            mapOf("type" to "first_analysis_reminder", "event_id" to "not-an-id"),
        )

        assertEquals(eventId, valid?.eventId)
        assertNull(malformed?.eventId)
    }
}
