package com.riskdetectedan.core.data.notebook

import com.riskdetectedan.core.data.notifications.DeviceTokenRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.serialization.json.*
import java.util.Base64
import java.util.UUID
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotebookRepository @Inject constructor(
    private val client: SupabaseClient,
    storage: NotebookEncryptedStorage,
    private val deviceTokens: DeviceTokenRepository,
) {
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
    suspend fun reminders(expected: NotebookIdentity): List<NotebookReminder> {
        if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
        val result = mutableListOf<NotebookReminder>()
        var after: String? = null
        repeat(50) {
            val raw = client.postgrest.rpc("isg_notebook_reminders_v1", buildJsonObject {
                if (after == null) put("p_after", JsonNull) else put("p_after", after!!)
            }).data
            currentCoroutineContext().ensureActive()
            if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
            require(raw.toByteArray(Charsets.UTF_8).size <= 2_000_000)
            val page = Json.decodeFromString<NotebookReminderPage>(raw).also { it.validate(after) }
            result += page.reminders
            require(result.size <= 1_000)
            if (!page.has_more) return result
            after = page.next_after
        }
        throw NotebookFailure("LIMIT")
    }
    /** A reminder, optionally tied to one note, delivered by this installation's server push registration. */
    suspend fun createReminder(title: String, recurrence: String, dueAt: Instant, expected: NotebookIdentity, note: String? = null) {
        if (identity() != expected || dueAt <= Instant.now() || title.isBlank() ||
            title.codePointCount(0, title.length) > 200 || recurrence !in setOf("once", "daily", "weekly", "monthly")) {
            throw NotebookFailure("INVALID")
        }
        val zoned = dueAt.atZone(ZoneId.systemDefault())
        reminderMutation(buildJsonObject {
            put("p_mutation", UUID.randomUUID().toString()); put("p_action", "create")
            put("p_reminder", JsonNull); put("p_note", note?.let(::JsonPrimitive) ?: JsonNull); put("p_occurrence", JsonNull); put("p_expected", 0)
            put("p_title", title); put("p_recurrence", recurrence)
            put("p_local_time", zoned.format(DateTimeFormatter.ofPattern("HH:mm:ss")))
            put("p_starts_on", zoned.format(DateTimeFormatter.ISO_LOCAL_DATE)); put("p_timezone", zoned.zone.id)
            put("p_snoozed_until", JsonNull); put("p_installation", deviceTokens.installationIdForServerPush())
        }, expected).also { receipt ->
            require(receipt["state"]?.jsonPrimitive?.content == "active")
            require(receipt["delivery_strategy"]?.jsonPrimitive?.content == "server_push")
        }
    }
    suspend fun settleReminder(action: String, reminder: NotebookReminder,
                               occurrence: NotebookReminderOccurrence? = null, snoozedUntil: Instant? = null,
                               expected: NotebookIdentity) {
        require(action in setOf("complete", "snooze", "cancel") && reminder.state == "active")
        require((action == "cancel") == (occurrence == null) && (action == "snooze") == (snoozedUntil != null))
        reminderMutation(buildJsonObject {
            put("p_mutation", UUID.randomUUID().toString()); put("p_action", action); put("p_reminder", reminder.reminder_id)
            put("p_note", JsonNull)
            if (occurrence == null) put("p_occurrence", JsonNull) else put("p_occurrence", occurrence.occurrence_id)
            put("p_expected", reminder.series_version); put("p_title", JsonNull); put("p_recurrence", JsonNull)
            put("p_local_time", JsonNull); put("p_starts_on", JsonNull); put("p_timezone", JsonNull)
            if (snoozedUntil == null) put("p_snoozed_until", JsonNull) else put("p_snoozed_until", snoozedUntil.toString())
            put("p_installation", JsonNull)
        }, expected)
    }
    private suspend fun reminderMutation(arguments: JsonObject, expected: NotebookIdentity): JsonObject {
        if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
        try {
            val raw = client.postgrest.rpc("isg_notebook_reminder_mutate_v1", arguments).data
            currentCoroutineContext().ensureActive()
            if (identity() != expected) throw NotebookFailure("IDENTITY_CHANGED")
            require(raw.toByteArray(Charsets.UTF_8).size <= 16_384)
            return Json.parseToJsonElement(raw).jsonObject.also {
                require(it["schema_version"]?.jsonPrimitive?.int == 1)
                require(it["mutation_id"]?.jsonPrimitive?.content == arguments.getValue("p_mutation").jsonPrimitive.content)
            }
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            val response = when (error) { is RestException -> error.response; is ResponseException -> error.response; else -> null }
            val body = response?.let { runCatching { Json.parseToJsonElement(it.bodyAsText()).jsonObject }.getOrNull() }
            val state = body?.get("code")?.jsonPrimitive?.content
            val code = body?.get("message")?.jsonPrimitive?.content
            if (state in setOf("P0001", "28000") && code in setOf("AUTH_REQUIRED", "FEATURE_UNAVAILABLE", "ACCESS_DENIED",
                    "VERSION_CONFLICT", "IDEMPOTENCY_CONFLICT", "VALIDATION_ERROR", "DEVICE_UNAVAILABLE")) {
                throw NotebookServerFailure(code!!)
            }
            if (error is CancellationException) throw error
            throw NotebookFailure("UNAVAILABLE")
        }
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
