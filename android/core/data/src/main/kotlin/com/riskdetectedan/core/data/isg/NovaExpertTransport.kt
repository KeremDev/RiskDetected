package com.riskdetectedan.core.data.isg

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import java.util.Base64
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** The organization an expert is working in. A request descriptor, never server authority. */
data class NovaExpertWorkspace(
    val workspaceId: String, val membershipId: String, val userId: String, val kind: String,
    val permissionRevision: Long, val workspaceVersion: Long, val canRead: Boolean, val canOperate: Boolean,
) {
    companion object {
        fun of(context: IsgWorkspaceContext) = NovaExpertWorkspace(context.workspaceId, context.membership.membershipId,
            context.membership.userId, context.kind, context.membership.permissionRevision, context.workspaceVersion,
            context.canRead, context.canOperate)
    }
}

/**
 * The expert UI has one implementation; its data boundary is either the signed-in
 * user's personal records or an explicitly selected organization (iOS `NovaExpertAccess`).
 */
data class NovaExpertAccess(val identity: IsgWorkspaceIdentity, val workspace: NovaExpertWorkspace?) {
    val workspaceId: String? get() = workspace?.workspaceId
    val canManageCompany: Boolean get() = workspace == null
    val canOperate: Boolean get() = workspace?.canOperate ?: true
    val storageNamespace: String get() = "${identity.userId}:${workspace?.workspaceId ?: "personal"}"

    fun validate(currentIdentity: IsgWorkspaceIdentity?, currentWorkspace: NovaExpertWorkspace?) {
        if (identity != currentIdentity || workspace != currentWorkspace ||
            (workspace != null && (workspace.userId != identity.userId || !workspace.canRead))) {
            throw NovaExpertFailure("ACCESS_DENIED")
        }
    }
}

class NovaExpertTicket internal constructor(val generation: String, val access: NovaExpertAccess)

/**
 * A server refusal. [code] is the application code the function raised
 * (`P0001`/`28000` only), or a class name for constraint violations, or
 * `UNAVAILABLE`. Server diagnostics never reach the UI.
 */
class NovaExpertFailure(val code: String, val sqlState: String? = null) : Exception(code)

/**
 * Composition boundary for the expert services (iOS `NovaExpertTransport`).
 * Each service captures a ticket, so a response from a previous workspace or
 * session cannot enter the new one, and a failed organization request never
 * falls back to a personal RPC.
 */
@Singleton
class NovaExpertTransport @Inject constructor(private val client: SupabaseClient) {
    @Volatile private var ticket: NovaExpertTicket? = null
    @Volatile private var currentWorkspace: () -> NovaExpertWorkspace? = { null }
    private val json = Json { ignoreUnknownKeys = true }

    fun identityNow(): IsgWorkspaceIdentity? = runCatching {
        val session = client.auth.currentSessionOrNull() ?: return null
        val user = client.auth.currentUserOrNull()?.id ?: return null
        val payload = json.parseToJsonElement(
            String(Base64.getUrlDecoder().decode(session.accessToken.split('.')[1]), Charsets.UTF_8)).jsonObject
        IsgWorkspaceIdentity(UUID.fromString(user).toString(),
            UUID.fromString(payload.getValue("session_id").jsonPrimitive.content).toString())
    }.getOrNull()

    @Synchronized
    fun bind(identity: IsgWorkspaceIdentity, workspace: NovaExpertWorkspace?,
             current: () -> NovaExpertWorkspace? = { workspace }): NovaExpertTicket {
        val value = NovaExpertTicket(UUID.randomUUID().toString(), NovaExpertAccess(identity, workspace))
        currentWorkspace = current
        ticket = value
        return value
    }

    @Synchronized
    fun release(expected: NovaExpertTicket) {
        if (ticket !== expected) return
        ticket = null
        currentWorkspace = { null }
    }

    fun capture(): NovaExpertTicket? = ticket

    suspend fun validate(expected: NovaExpertTicket?) {
        currentCoroutineContext().ensureActive()
        if (expected !== ticket) throw NovaExpertFailure("ACCESS_DENIED")
        expected?.access?.validate(identityNow(), currentWorkspace())
    }

    /**
     * Runs [function]. Organization tickets go through `isg_expert_rpc_v1` and
     * must come back stamped with the same workspace.
     */
    suspend fun execute(function: String, params: JsonObject, expected: NovaExpertTicket? = capture(),
                        maxBytes: Int = 25_165_824): JsonElement {
        validate(expected)
        val workspace = expected?.access?.workspaceId
        val result = if (workspace != null) {
            val envelope = rpc("isg_expert_rpc_v1", buildJsonObject {
                put("p_workspace", workspace); put("p_function", function); put("p_arguments", params)
            }, maxBytes) as? JsonObject ?: throw NovaExpertFailure("ACCESS_DENIED")
            if (envelope["_expert_workspace_id"]?.jsonPrimitive?.contentOrNull != workspace) throw NovaExpertFailure("ACCESS_DENIED")
            envelope["payload"] ?: throw NovaExpertFailure("ACCESS_DENIED")
        } else rpc(function, params, maxBytes)
        validate(expected)
        return result
    }

    suspend fun executeObject(function: String, params: JsonObject, expected: NovaExpertTicket? = capture(),
                              maxBytes: Int = 25_165_824): JsonObject =
        execute(function, params, expected, maxBytes) as? JsonObject ?: throw NovaExpertFailure("UNAVAILABLE")

    private suspend fun rpc(function: String, params: JsonObject, maxBytes: Int): JsonElement = try {
        val raw = client.postgrest.rpc(function, params).data
        if (raw.toByteArray(Charsets.UTF_8).size > maxBytes) throw NovaExpertFailure("UNAVAILABLE")
        json.parseToJsonElement(raw)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: NovaExpertFailure) {
        throw failure
    } catch (error: Exception) {
        currentCoroutineContext().ensureActive()
        val response = when (error) {
            is RestException -> error.response
            is ResponseException -> error.response
            else -> null
        }
        val body = response?.let { runCatching { json.parseToJsonElement(it.bodyAsText()).jsonObject }.getOrNull() }
        val state = body?.get("code")?.jsonPrimitive?.contentOrNull
        val message = body?.get("message")?.jsonPrimitive?.contentOrNull
        throw when {
            state in setOf("P0001", "28000") && message != null && message.matches(Regex("[A-Z][A-Z0-9_]{2,63}")) ->
                NovaExpertFailure(message, state)
            state in setOf("23503", "23505", "23514", "23P01", "22007", "22008", "22P02") ->
                NovaExpertFailure("VALIDATION_ERROR", state)
            else -> NovaExpertFailure("UNAVAILABLE", state)
        }
    }
}
