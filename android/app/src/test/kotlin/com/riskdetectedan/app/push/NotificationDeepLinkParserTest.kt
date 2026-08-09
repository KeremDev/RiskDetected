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
}
