package com.riskdetectedan.core.data.notebook

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class NotebookReaderTest {
    private val identity = NotebookIdentity(UUID.randomUUID(), UUID.randomUUID())
    private val note = UUID.randomUUID().toString()
    private fun record(version: Long, deleted: Boolean = false) = NotebookRecord(note, if (deleted) null else "Not", if (deleted) null else "Metin", version, deleted, "2026-09-13T00:00:00Z")
    private fun page(rows: List<NotebookRecord>, more: Boolean = false, after: String? = null) = buildJsonObject {
        put("schema_version", 1); put("scan_mode", "full_scan_restart"); put("notes", Json.parseToJsonElement(Json.encodeToString(rows)))
        put("has_more", more); put("next_after", after?.let(::JsonPrimitive) ?: JsonNull)
    }.toString()
    @Test fun staleAndAbsentRecordsNeverRemoveOrDowngrade() = runBlocking {
        var response = page(listOf(record(2)))
        val reader = NotebookReader({ identity }) { assertNull(it); response }
        reader.refresh(identity)
        response = page(listOf(record(1))); reader.refresh(identity)
        response = page(emptyList()); reader.refresh(identity)
        assertEquals(2L, reader.snapshot(identity, emptyList()).notes.single().version)
    }
    @Test fun tombstoneCannotBeResurrectedAndDraftIsPreserved() = runBlocking {
        var response = page(listOf(record(3, true)))
        val reader = NotebookReader({ identity }) { response }; reader.refresh(identity)
        response = page(listOf(record(4))); reader.refresh(identity)
        val draft = NotebookPending(NotebookMutation(UUID.randomUUID().toString(), note, "sync", 2, "draft", null, null))
        val snapshot = reader.snapshot(identity, listOf(draft))
        assertTrue(snapshot.notes.isEmpty()); assertEquals(listOf(draft), snapshot.drafts)
    }
    @Test fun identityChangeDuringRequestDiscardsResponse() = runBlocking {
        var current = identity
        val other = NotebookIdentity(UUID.randomUUID(), UUID.randomUUID())
        val reader = NotebookReader({ current }) { current = other; page(listOf(record(1))) }
        try { reader.refresh(identity); fail() } catch (_: NotebookFailure) {}
        assertTrue(reader.snapshot(other, emptyList()).notes.isEmpty())
    }
    @Test fun failedSecondPagePublishesNothing() = runBlocking {
        val rows = (1..20).map { record(1).copy(note_id = "00000000-0000-0000-0000-" + it.toString().padStart(12, '0')) }
        var calls = 0
        val reader = NotebookReader({ identity }) { cursor ->
            calls++; if (cursor != null) throw NotebookFailure("UNAVAILABLE")
            page(rows, true, rows.last().note_id)
        }
        try { reader.refresh(identity); fail() } catch (_: NotebookFailure) {}
        assertEquals(2, calls); assertTrue(reader.snapshot(identity, emptyList()).notes.isEmpty())
    }
    @Test fun malformedCursorAndEqualVersionMismatchFailClosed() = runBlocking {
        var response = page(listOf(record(1)))
        val reader = NotebookReader({ identity }) { response }; reader.refresh(identity)
        response = page(listOf(record(1).copy(body = "different")))
        try { reader.refresh(identity); fail() } catch (_: IllegalArgumentException) {}
        assertEquals("Metin", reader.snapshot(identity, emptyList()).notes.single().body)
        response = page(listOf(record(2)), true, note)
        try { reader.refresh(identity); fail() } catch (_: IllegalArgumentException) {}
        assertEquals(1L, reader.snapshot(identity, emptyList()).notes.single().version)
    }
}
