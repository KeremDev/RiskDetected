package com.riskdetectedan.core.data.notebook

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.serialization.json.*
import java.util.Base64
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotebookRepository @Inject constructor(private val client: SupabaseClient, storage: NotebookEncryptedStorage) {
    val identities get() = client.auth.sessionStatus.map { identity() }.distinctUntilChanged()
    val reader = NotebookReader({ identity() }) { after ->
        client.postgrest.rpc("isg_notebook_read_v1", buildJsonObject {
            put("p_note", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull)
        }).data
    }
    suspend fun snapshot(identity: NotebookIdentity): NotebookReader.Snapshot = reader.snapshot(identity, queue.pending(identity))
    suspend fun organization(note: String, expected: NotebookIdentity): NotebookOrganization {
        if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
        val raw = client.postgrest.rpc("isg_notebook_organization_v1", buildJsonObject { put("p_note", note) }).data
        currentCoroutineContext().ensureActive()
        if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
        require(raw.toByteArray(Charsets.UTF_8).size <= 2_000_000)
        return Json.decodeFromString<NotebookOrganization>(raw).also { it.validate(note) }
    }
    suspend fun conflict(pending: NotebookPending, expected: NotebookIdentity): Pair<NotebookRecord, NotebookConflict> {
        if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
        val wanted = pending.conflictID ?: throw NotebookFailure("INVALID")
        var after: String? = null; var version: Long? = null
        repeat(50) {
            val raw = client.postgrest.rpc("isg_notebook_read_v1", buildJsonObject {
                put("p_note", pending.intent.note); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull)
            }).data
            currentCoroutineContext().ensureActive()
            if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
            require(raw.toByteArray(Charsets.UTF_8).size <= 2_000_000)
            val page = Json.decodeFromString<NotebookConflictPage>(raw); page.validate(pending.intent.note, after)
            if (page.note.tombstone) throw NotebookServerFailure("NOTE_TOMBSTONED")
            if (version != null && version != page.note.version) throw NotebookFailure("UNAVAILABLE")
            version = page.note.version
            page.note.conflicts.find { it.conflict_id == wanted }?.let { return page.note.record() to it }
            if (!page.has_more_conflicts) throw NotebookServerFailure("CONFLICT_ALREADY_RESOLVED")
            after = page.next_conflict_after
        }
        throw NotebookFailure("LIMIT")
    }
    fun identity(): NotebookIdentity? = runCatching {
        val session = client.auth.currentSessionOrNull() ?: return null
        val owner = client.auth.currentUserOrNull()?.id ?: return null
        val body = Json.parseToJsonElement(String(Base64.getUrlDecoder().decode(session.accessToken.split('.')[1]), Charsets.UTF_8)).jsonObject
        NotebookIdentity(UUID.fromString(owner), UUID.fromString(body.getValue("session_id").jsonPrimitive.content))
    }.getOrNull() // Identity correlation only; PostgreSQL validates the session.
    val queue = NotebookQueue(storage, { identity() }) { args ->
        try {
            val raw = client.postgrest.rpc(if ("p_items" in args) "isg_notebook_organize_v1" else "isg_notebook_mutate_v1", args).data
            if (raw.toByteArray(Charsets.UTF_8).size > 16384) throw NotebookFailure("INVALID_RESPONSE")
            Json.parseToJsonElement(raw).jsonObject
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            val response = when (error) { is RestException -> error.response; is ResponseException -> error.response; else -> null }
            val body = response?.let { runCatching { Json.parseToJsonElement(it.bodyAsText()).jsonObject }.getOrNull() }
            val state = body?.get("code")?.jsonPrimitive?.content
            val code = body?.get("message")?.jsonPrimitive?.content
            if (state in setOf("P0001", "28000") && code in setOf("AUTH_REQUIRED", "FEATURE_UNAVAILABLE", "ACCESS_DENIED", "VERSION_CONFLICT", "NOTE_TOMBSTONED", "IDEMPOTENCY_CONFLICT", "VALIDATION_ERROR", "CONFLICT_ALREADY_RESOLVED")) throw NotebookServerFailure(code!!)
            throw NotebookFailure("UNAVAILABLE")
        }
    }
}
