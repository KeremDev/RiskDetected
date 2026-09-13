package com.riskdetectedan.core.data.notebook

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

@Serializable
data class NotebookRecord(val note_id: String, val title: String?, val body: String?, val version: Long,
    val tombstone: Boolean, val updated_at: String) {
    fun validate() {
        require(UUID.fromString(note_id).toString() == note_id && version in 1..9007199254740991L && updated_at.isNotEmpty())
        require((title?.codePointCount(0, title.length) ?: 0) <= 200 && (body?.codePointCount(0, body.length) ?: 0) <= 20000)
        require(!tombstone || (title == null && body == null))
    }
}

/** Session-only read model; durable edits stay in the separate encrypted outbox. */
class NotebookReader(private val current: () -> NotebookIdentity?, private val read: suspend (String?) -> String) {
    data class Snapshot(val notes: List<NotebookRecord>, val drafts: List<NotebookPending>)
    @Serializable private data class Page(val schema_version: Int, val scan_mode: String, val notes: List<NotebookRecord>,
        val has_more: Boolean, val next_after: String?)
    private val lock = Mutex()
    private var bound: NotebookIdentity? = null
    private var records = mapOf<String, NotebookRecord>()
    private suspend fun check(identity: NotebookIdentity) {
        currentCoroutineContext().ensureActive()
        if (current() != identity) { records = emptyMap(); bound = null; throw NotebookFailure("IDENTITY_CHANGED") }
        if (bound != identity) { records = emptyMap(); bound = identity }
    }
    suspend fun snapshot(identity: NotebookIdentity, drafts: List<NotebookPending>): Snapshot = lock.withLock {
        check(identity); Snapshot(records.values.filterNot { it.tombstone }.sortedBy { it.note_id }, drafts)
    }
    suspend fun refresh(identity: NotebookIdentity) = lock.withLock {
        check(identity)
        var after: String? = null
        val merged = records.toMutableMap()
        repeat(50) {
            val raw = try { read(after) } catch (error: Exception) { check(identity); throw NotebookFailure("UNAVAILABLE") }
            check(identity); require(raw.toByteArray(Charsets.UTF_8).size <= 2_000_000)
            val page = Json.decodeFromString<Page>(raw)
            require(page.schema_version == 1 && page.scan_mode == "full_scan_restart" && page.notes.size <= 20)
            require(if (page.has_more) page.notes.size == 20 && page.next_after == page.notes.last().note_id else page.next_after == null)
            var previous = after ?: ""
            for (record in page.notes) {
                record.validate(); require(record.note_id > previous); previous = record.note_id
                val old = merged[record.note_id]
                if (old != null) {
                    if (old.tombstone || record.version < old.version) continue
                    if (old.version == record.version) { require(old == record); continue }
                }
                merged[record.note_id] = record
            }
            if (merged.size > 1000 || Json.encodeToString(merged.values.toList()).toByteArray(Charsets.UTF_8).size > 2_000_000) throw NotebookFailure("QUEUE_FULL")
            if (!page.has_more) { records = merged; return@withLock }
            after = page.next_after
        }
        throw NotebookFailure("QUEUE_FULL")
    }
}
