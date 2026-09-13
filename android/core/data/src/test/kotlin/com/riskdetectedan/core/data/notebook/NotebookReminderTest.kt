package com.riskdetectedan.core.data.notebook

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class NotebookReminderTest {
    @Test fun serverPushPageValidatesOwnerAndOccurrence() {
        val installation = UUID.randomUUID().toString()
        val page = Json.decodeFromString<NotebookReminderPage>("""{
          "schema_version":1,"delivery_mode":"server_push","has_more":false,"next_after":null,
          "reminders":[{"reminder_id":"00000000-0000-0000-0000-000000000001","note_id":null,
          "title":"Kontrol","recurrence":"daily","local_time":"09:00:00","starts_on":"2026-09-14",
          "timezone":"Europe/Istanbul","series_version":1,"state":"active","updated_at":"2026-09-13T16:00:00Z",
          "delivery_strategy":"server_push","delivery_installation_id":"$installation",
          "next_occurrence":{"occurrence_id":"00000000-0000-0000-0000-000000000002","occurrence_no":1,
          "series_version":1,"due_at":"2026-09-14T06:00:00Z","effective_due_at":"2026-09-14T06:00:00Z",
          "state":"scheduled","snoozed_until":null}}]}
        """)
        page.validate(null)
        assertEquals(installation, page.reminders.single().delivery_installation_id)
        assertTrue(runCatching { page.copy(delivery_mode = "local").validate(null) }.isFailure)
    }
}
