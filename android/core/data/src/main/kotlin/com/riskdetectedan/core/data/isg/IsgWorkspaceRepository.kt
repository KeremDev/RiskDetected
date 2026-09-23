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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

data class IsgWorkspaceIdentity(val userId: String, val sessionId: String)

/**
 * Real Supabase transport for the tenant-native Android product surface.
 *
 * Scope is pinned before every request and checked again by [IsgWorkspaceGateway]
 * after suspension. A workspace failure never falls back to owner-scoped legacy
 * endpoints, which keeps personal accounts and OSGB tenants separate.
 */
@Singleton
class IsgWorkspaceRepository @Inject constructor(private val client: SupabaseClient) {
    private data class Scope(
        val token: String,
        val identity: IsgWorkspaceIdentity,
        val workspaceId: String? = null,
        val membershipId: String? = null,
        val permissionRevision: Long? = null,
        val companyId: String? = null,
    )

    @Volatile private var scope: Scope? = null
    private val json = Json { ignoreUnknownKeys = false }
    private val gateway = IsgWorkspaceGateway(
        transport = ::rpc,
        isCurrentIdentity = { user, session -> identityNow() == IsgWorkspaceIdentity(user, session) },
        isCurrentWorkspace = { workspace, membership, revision ->
            scope?.let {
                it.workspaceId == workspace && it.membershipId == membership &&
                    it.permissionRevision == revision && identityNow() == it.identity
            } == true
        },
        currentScopeToken = { scope?.takeIf { identityNow() == it.identity }?.token },
    )

    fun identityNow(): IsgWorkspaceIdentity? = runCatching {
        val session = client.auth.currentSessionOrNull() ?: return null
        val user = client.auth.currentUserOrNull()?.id ?: return null
        val payload = json.parseToJsonElement(
            String(Base64.getUrlDecoder().decode(session.accessToken.split('.')[1]), Charsets.UTF_8),
        ).jsonObject
        val sessionId = payload.getValue("session_id").jsonPrimitive.content
        IsgWorkspaceIdentity(UUID.fromString(user).toString(), UUID.fromString(sessionId).toString())
    }.getOrNull()

    suspend fun listOsgbWorkspaces(): List<IsgWorkspaceContext> {
        val identity = identityNow() ?: throw IsgWorkspaceGatewayFailure("AUTH_REQUIRED")
        scope = Scope(UUID.randomUUID().toString(), identity)
        return gateway.list(identity.userId, identity.sessionId).filter { it.kind == "osgb" }
    }

    fun select(context: IsgWorkspaceContext, companyId: String? = null) {
        val identity = identityNow() ?: throw IsgWorkspaceGatewayFailure("AUTH_REQUIRED")
        if (context.membership.userId != identity.userId || !context.canRead) {
            throw IsgWorkspaceGatewayFailure("ACCESS_DENIED")
        }
        scope = Scope(
            token = UUID.randomUUID().toString(),
            identity = identity,
            workspaceId = context.workspaceId,
            membershipId = context.membership.membershipId,
            permissionRevision = context.membership.permissionRevision,
            companyId = companyId,
        )
    }

    fun clearSelection() {
        scope = null
    }

    suspend fun companies(context: IsgWorkspaceContext, after: String? = null, limit: Int = 100): JsonObject = inScope(context) {
        gateway.companies(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, after, limit)
    }

    suspend fun dashboard(context: IsgWorkspaceContext, companyId: String?): JsonObject =
        inScope(context, companyId) {
            gateway.dashboard(context.workspaceId, context.membership.membershipId,
                context.membership.permissionRevision, companyId)
        }

    suspend fun domain(context: IsgWorkspaceContext, companyId: String,
                       domain: IsgWorkspaceDomain): JsonObject = inScope(context, companyId) {
        gateway.domain(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, companyId, domain)
    }

    suspend fun domainMetrics(context: IsgWorkspaceContext, companyId: String,
                              domain: IsgWorkspaceDomain): JsonObject? = inScope(context, companyId) {
        gateway.domainMetrics(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, companyId, domain)
    }

    suspend fun personnelAdvanced(context: IsgWorkspaceContext, companyId: String,
                                  kind: IsgWorkspacePersonnelAdvancedKind): JsonObject = inScope(context, companyId) {
        gateway.personnelAdvanced(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, companyId, kind)
    }

    suspend fun trainingAdvanced(context: IsgWorkspaceContext, companyId: String,
                                 kind: IsgWorkspaceTrainingAdvancedKind): JsonObject = inScope(context, companyId) {
        gateway.trainingAdvanced(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, companyId, kind)
    }

    suspend fun analyses(context: IsgWorkspaceContext, companyId: String): JsonObject = inScope(context, companyId) {
        gateway.analyses(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, companyId)
    }

    suspend fun analysis(context: IsgWorkspaceContext, companyId: String, analysisId: String): JsonObject =
        inScope(context, companyId) {
            gateway.analysis(context.workspaceId, context.membership.membershipId,
                context.membership.permissionRevision, companyId, analysisId)
        }

    suspend fun createExport(context: IsgWorkspaceContext, companyId: String, analysisId: String,
                             format: String): JsonObject = inScope(context, companyId) {
        gateway.createExport(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, context.canOperate, UUID.randomUUID().toString(),
            companyId, analysisId, format, emptyList(), emptyList(), emptyList())
    }

    /** One domain's rows with its counters; a domain without counters shows its rows alone. */
    suspend fun snapshot(context: IsgWorkspaceContext, companyId: String, domain: IsgWorkspaceDomain): IsgWorkspaceSnapshot {
        val page = domain(context, companyId, domain)
        val metrics = try { domainMetrics(context, companyId, domain) } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { null }
        return IsgWorkspaceRecords.snapshot(domain, page, metrics)
    }

    suspend fun personnelMetrics(context: IsgWorkspaceContext, companyId: String?): JsonObject = inScope(context, companyId) {
        gateway.personnelMetrics(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, companyId)
    }

    /**
     * Every active workplace, department or employee of a company as id to name (iOS `directory` / `employees`),
     * reading until the cursor ends; ids are lowercased so facts in either case resolve.
     */
    suspend fun directory(context: IsgWorkspaceContext, companyId: String, kind: String, archived: Boolean = false): List<Pair<String, String>> =
        inScope(context, companyId) {
            val key = when (kind) { "workplaces" -> "workplace_id"; "departments" -> "department_id"; else -> "employee_id" }
            val rows = mutableListOf<Pair<String, String>>()
            var cursor: String? = null
            var pages = 0
            do {
                if (++pages > 100) throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
                val page = gateway.personnelRead(context.workspaceId, context.membership.membershipId,
                    context.membership.permissionRevision, companyId, kind, archived = archived, after = cursor)
                page["rows"]!!.jsonArray.forEach { item ->
                    val row = item.jsonObject
                    val id = row[key]?.jsonPrimitive?.contentOrNull ?: throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
                    rows += id.lowercase() to (row["name"]?.jsonPrimitive?.contentOrNull ?: "")
                }
                val next = (page["next"] as? JsonPrimitive)?.contentOrNull
                if (next != null && next == cursor) throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
                cursor = next
            } while (cursor != null)
            rows
        }

    suspend fun search(context: IsgWorkspaceContext, companyId: String, query: String): JsonObject = inScope(context, companyId) {
        gateway.search(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, companyId, query)
    }

    suspend fun changes(context: IsgWorkspaceContext, companyId: String?, limit: Int = 100): JsonObject = inScope(context, companyId) {
        gateway.changes(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, companyId, limit = limit)
    }

    private suspend fun <T> inScope(context: IsgWorkspaceContext, companyId: String? = null,
                                    block: suspend () -> T): T {
        select(context, companyId)
        return block()
    }

    private suspend fun rpc(function: String, arguments: JsonObject): JsonObject = try {
        val raw = client.postgrest.rpc(function, arguments).data
        require(raw.toByteArray(Charsets.UTF_8).size <= 16_777_216)
        json.parseToJsonElement(raw).jsonObject
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        currentCoroutineContext().ensureActive()
        val response = when (error) {
            is RestException -> error.response
            is ResponseException -> error.response
            else -> null
        }
        val body = response?.let {
            runCatching { json.parseToJsonElement(it.bodyAsText()).jsonObject }.getOrNull()
        }
        val code = body?.get("code")?.jsonPrimitive?.content
        val message = body?.get("message")?.jsonPrimitive?.content
        val safe = if (code in setOf("P0001", "28000") && message in SAFE_ERRORS) message else "UNAVAILABLE"
        throw IsgWorkspaceGatewayFailure(safe ?: "UNAVAILABLE")
    }

    private companion object {
        val SAFE_ERRORS = setOf(
            "AUTH_REQUIRED", "ACCESS_DENIED", "FEATURE_UNAVAILABLE", "DOMAIN_UNAVAILABLE",
            "WORKSPACE_INACTIVE", "ASSIGNMENT_REQUIRED", "VALIDATION_ERROR", "VERSION_CONFLICT",
            "SEAT_LIMIT_REACHED", "INSUFFICIENT_CREDITS", "QUOTA_EXCEEDED", "PURCHASE_PENDING",
        )
    }
}
