package com.riskdetectedan.core.data.notebook

import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class NotebookConflictTest {
    private val note = UUID.randomUUID().toString()
    private val conflict = NotebookConflict(UUID.randomUUID().toString(), 0, 1, "local", "local body", "remote", "remote body")
    private fun page() = NotebookConflictPage(1, NotebookConflictDetail(note, "current", "body", 2, false, "2026-09-13T00:00:00Z", listOf(conflict)), false, null)
    @Test fun validConflictPreservesBothTexts() {
        val page = page(); page.validate(note, null)
        assertEquals("local body", page.note.conflicts.single().incoming_body)
        assertEquals("remote body", page.note.conflicts.single().server_body)
    }
    @Test fun foreignNoteAndMalformedCursorRejected() {
        try { page().validate(UUID.randomUUID().toString(), null); fail() } catch (_: IllegalArgumentException) {}
        try { page().copy(has_more_conflicts = true).validate(note, null); fail() } catch (_: IllegalArgumentException) {}
    }
    @Test fun tombstoneCannotCarryConflicts() {
        val bad = page().copy(note = page().note.copy(tombstone = true, title = null, body = null))
        try { bad.validate(note, null); fail() } catch (_: IllegalArgumentException) {}
    }
    @Test fun futureVersionDuplicateAndOversizedTextRejected() {
        for (rows in listOf(listOf(conflict.copy(server_version = 3)), listOf(conflict, conflict), listOf(conflict.copy(incoming_body = "a".repeat(20001))))) {
            try { page().copy(note = page().note.copy(conflicts = rows)).validate(note, null); fail() } catch (_: IllegalArgumentException) {}
        }
    }
}
