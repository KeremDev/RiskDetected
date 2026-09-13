package com.riskdetectedan.core.data.notebook

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import java.util.Base64
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotebookRepository @Inject constructor(private val client: SupabaseClient, storage: NotebookEncryptedStorage) {
    val reader = NotebookReader({ identity() }) { after ->
        client.postgrest.rpc("isg_notebook_read_v1", buildJsonObject {
            put("p_note", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull)
        }).data
    }
    suspend fun snapshot(identity: NotebookIdentity): NotebookReader.Snapshot = reader.snapshot(identity, queue.pending(identity))
    fun identity(): NotebookIdentity? = runCatching {
        val session = client.auth.currentSessionOrNull() ?: return null
        val owner = client.auth.currentUserOrNull()?.id ?: return null
        val body = Json.parseToJsonElement(String(Base64.getUrlDecoder().decode(session.accessToken.split('.')[1]), Charsets.UTF_8)).jsonObject
        NotebookIdentity(UUID.fromString(owner), UUID.fromString(body.getValue("session_id").jsonPrimitive.content))
    }.getOrNull() // Identity correlation only; PostgreSQL validates the session.
    val queue = NotebookQueue(storage, { identity() }) { args ->
        try {
            val raw = client.postgrest.rpc("isg_notebook_mutate_v1", args).data
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
