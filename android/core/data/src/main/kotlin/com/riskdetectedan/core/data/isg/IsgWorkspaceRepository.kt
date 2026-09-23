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
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.storage.storage
import io.ktor.client.statement.readRawBytes
import kotlinx.serialization.json.*
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

    private suspend fun <T> pages(read: suspend (String?) -> JsonObject, parse: (JsonObject) -> T, id: (T) -> String): List<T> {
        val rows = mutableListOf<T>()
        var cursor: String? = null
        var pages = 0
        do {
            if (++pages > 100) throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
            val page = read(cursor)
            val values = page["rows"]!!.jsonArray.map { parse(it.jsonObject) }
            rows += values
            val next = (page["next"] as? JsonPrimitive)?.contentOrNull
            if (next != null && (next == cursor || next != values.lastOrNull()?.let(id))) throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
            cursor = next
        } while (cursor != null)
        return rows
    }

    suspend fun members(context: IsgWorkspaceContext, status: String = "all"): List<IsgWorkspaceMember> = inScope(context) {
        pages({ gateway.members(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, status, it) },
            IsgWorkspaceMember::parse) { it.id }
    }

    suspend fun invitations(context: IsgWorkspaceContext, status: String = "all"): List<IsgWorkspaceInvitation> = inScope(context) {
        pages({ gateway.invitations(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, status, it) },
            IsgWorkspaceInvitation::parse) { it.id }
    }

    suspend fun invite(context: IsgWorkspaceContext, mutationId: String, email: String, role: String, expiresAt: String) = inScope(context) {
        IsgWorkspaceInvitationToken.parse(gateway.invite(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, mutationId, email, role, expiresAt))
    }

    suspend fun resendInvitation(context: IsgWorkspaceContext, mutationId: String, invitation: IsgWorkspaceInvitation, expiresAt: String) =
        inScope(context) {
            IsgWorkspaceInvitationToken.parse(gateway.resendInvitation(context.workspaceId, context.membership.membershipId,
                context.membership.permissionRevision, mutationId, invitation.id, invitation.version, expiresAt))
        }

    suspend fun revokeInvitation(context: IsgWorkspaceContext, mutationId: String, invitation: IsgWorkspaceInvitation) = inScope(context) {
        gateway.revokeInvitation(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
            mutationId, invitation.id, invitation.version)
    }

    suspend fun mutateMember(context: IsgWorkspaceContext, mutationId: String, member: IsgWorkspaceMember, action: String,
                             value: String? = null, reason: String? = null) = inScope(context) {
        IsgWorkspaceMember.parse(gateway.mutateMember(context.workspaceId, context.membership.membershipId,
            context.membership.permissionRevision, mutationId, member.id, member.version, action, value, reason))
    }

    suspend fun assignments(context: IsgWorkspaceContext, companyId: String): List<IsgWorkspaceAssignment> = inScope(context, companyId) {
        pages({ gateway.assignments(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, companyId, after = it) },
            IsgWorkspaceAssignment::parse) { it.id }
    }

    suspend fun mutateAssignment(context: IsgWorkspaceContext, mutationId: String, companyId: String, action: String,
                                 assignmentId: String? = null, membershipId: String? = null, expectedVersion: Long = 0,
                                 role: String? = null, startsAt: String? = null, endsAt: String? = null, reason: String) =
        inScope(context, companyId) {
            IsgWorkspaceAssignment.parse(gateway.mutateAssignment(context.workspaceId, context.membership.membershipId,
                context.membership.permissionRevision, context.canOperate, mutationId, companyId, action, assignmentId, membershipId,
                expectedVersion, role, startsAt, endsAt, reason))
        }

    /**
     * Creates or updates a company, then its profile, as two replay-safe mutations (iOS `createCompany` /
     * `updateCompany`). Returns the company id.
     */
    suspend fun saveCompany(context: IsgWorkspaceContext, mutationId: String, profileMutationId: String, companyId: String?,
                            expectedVersion: Long, expectedProfileVersion: Long, draft: IsgWorkspaceCompanyDraft): String = inScope(context) {
        val company = gateway.saveCompany(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
            context.canOperate, mutationId, companyId, expectedVersion, draft.name, draft.hazardClass)["company_id"]!!.jsonPrimitive.content
        gateway.mutateCompanyProfile(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
            context.canOperate, profileMutationId, company, if (companyId == null) 0 else expectedProfileVersion, draft.sector, draft.email,
            draft.employeeCount, draft.address, draft.responsibleName, draft.responsiblePhone, draft.responsibleEmail)
        company
    }

    suspend fun archiveCompany(context: IsgWorkspaceContext, mutationId: String, companyId: String, expectedVersion: Long, reason: String) =
        inScope(context) {
            gateway.archiveCompany(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
                context.canOperate, mutationId, companyId, expectedVersion, reason)
        }

    suspend fun mutateDomain(context: IsgWorkspaceContext, mutationId: String, companyId: String, domain: IsgWorkspaceDomain,
                             payload: JsonObject): JsonObject = inScope(context, companyId) {
        gateway.mutateDomain(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
            context.canOperate, mutationId, companyId, domain, payload)
    }

    /**
     * Uploads one file into the company archive (iOS `uploadFile`): a replayed mutation returns its existing entry,
     * otherwise the bytes go to the exact private path the server opened, are finalized by the inspection worker,
     * and only then become a file entry. Returns the entry and asset ids.
     */
    suspend fun uploadFile(context: IsgWorkspaceContext, mutationId: String, companyId: String, title: String, filename: String,
                           category: String, data: ByteArray): Pair<String, String> = inScope(context, companyId) {
        val cleanTitle = title.trim(); val cleanName = filename.trim()
        val extension = cleanName.substringAfterLast('.', "").lowercase()
        if (cleanTitle.isEmpty() || cleanTitle.toByteArray().size > 320 || cleanName.isEmpty() || cleanName.toByteArray().size > 400 ||
            extension !in FILE_TYPES || category !in FILE_CATEGORIES || data.size !in 1..52_428_800)
            throw IsgWorkspaceGatewayFailure("VALIDATION_ERROR")
        val ids = Triple(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision)
        val receipt = gateway.fileCreateReceipt(ids.first, ids.second, ids.third, context.canOperate, companyId, mutationId)
        if (receipt["found"]?.jsonPrimitive?.booleanOrNull == true) {
            val entry = receipt["entry_id"]?.jsonPrimitive?.contentOrNull; val asset = receipt["asset_id"]?.jsonPrimitive?.contentOrNull
            if (entry == null || asset == null || receipt["byte_size"]?.jsonPrimitive?.longOrNull != data.size.toLong())
                throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
            return@inScope entry to asset
        }
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
        val mediaType = FILE_TYPES.getValue(extension)
        val opened = gateway.uploadOpen(ids.first, ids.second, ids.third, context.canOperate, companyId, UUID.randomUUID().toString(), digest,
            mediaType, extension, data.size, java.time.Instant.now().plusSeconds(600).truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString())
        client.storage.from(opened["bucket"]!!.jsonPrimitive.content).upload(opened["object_path"]!!.jsonPrimitive.content, data) {
            upsert = false; contentType = io.ktor.http.ContentType.parse(mediaType)
        }
        val finalized = json.parseToJsonElement(client.functions.invoke("isg-workspace-file-finalize",
            body = buildJsonObject { put("upload_token", opened["upload_token"]!!.jsonPrimitive.content) }).bodyAsText()).jsonObject
        val asset = finalized["asset_id"]?.jsonPrimitive?.contentOrNull
        if (finalized["schema_version"]?.jsonPrimitive?.intOrNull != 1 || finalized["workspace_id"]?.jsonPrimitive?.contentOrNull != context.workspaceId ||
            finalized["byte_size"]?.jsonPrimitive?.longOrNull != data.size.toLong() || asset == null) throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
        val entry = gateway.mutateDomain(ids.first, ids.second, ids.third, context.canOperate, mutationId, companyId, IsgWorkspaceDomain.FILES,
            buildJsonObject {
                put("action", "create"); put("asset_id", asset); put("category", category); put("visibility", "company_team")
                put("title", cleanTitle); put("original_filename", cleanName); put("note", ""); put("tags", JsonArray(emptyList()))
            })
        (IsgWorkspaceMutations.recordId(entry) ?: throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")) to asset
    }

    /** The bytes of one workspace asset, through a short-lived download grant. */
    suspend fun downloadAsset(context: IsgWorkspaceContext, assetId: String): ByteArray = inScope(context) {
        val token = gateway.downloadOpen(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, assetId,
            java.time.Instant.now().plusSeconds(120).truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString())
        val bytes = client.functions.invoke("isg-workspace-file-download", body = buildJsonObject { put("download_token", token) }).readRawBytes()
        if (bytes.isEmpty() || bytes.size > 52_428_800) throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
        bytes
    }

    suspend fun domainDetail(context: IsgWorkspaceContext, companyId: String, domain: IsgWorkspaceDomain, id: String): IsgWorkspaceRecord =
        inScope(context, companyId) {
            IsgWorkspaceRecords.record(gateway.domainDetail(context.workspaceId, context.membership.membershipId,
                context.membership.permissionRevision, companyId, domain, id), domain)
        }

    /** Checklist templates as (id "code:version", code, version, title, item count). */
    suspend fun checklistTemplates(context: IsgWorkspaceContext, companyId: String): List<IsgWorkspaceChecklistTemplate> = inScope(context, companyId) {
        gateway.checklistTemplates(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, companyId).map {
            val row = it.jsonObject
            IsgWorkspaceChecklistTemplate(row["code"]!!.jsonPrimitive.content, row["version"]!!.jsonPrimitive.int,
                row["title"]!!.jsonPrimitive.content, row["item_count"]!!.jsonPrimitive.int)
        }
    }

    suspend fun equipmentCatalog(context: IsgWorkspaceContext, companyId: String): IsgWorkspaceEquipmentCatalog = inScope(context, companyId) {
        val root = gateway.equipmentCatalog(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision, companyId)
        IsgWorkspaceEquipmentCatalog(
            root["suggestions"]!!.jsonArray.map { it.jsonObject }.map {
                IsgWorkspaceEquipmentCatalog.Suggestion(it["code"]!!.jsonPrimitive.content, it["ordinal"]!!.jsonPrimitive.int,
                    it["default_period_months"]?.jsonPrimitive?.intOrNull, it["default_basis_note"]?.jsonPrimitive?.contentOrNull)
            }.sortedBy { it.ordinal },
            root["rules"]!!.jsonArray.map { it.jsonObject }.map {
                IsgWorkspaceEquipmentCatalog.Rule(it["equipment_type"]!!.jsonPrimitive.content, it["period_months"]!!.jsonPrimitive.int,
                    it["period_source"]?.jsonPrimitive?.contentOrNull.orEmpty(), it["needs_review"]?.jsonPrimitive?.booleanOrNull == true,
                    it["exception_note"]?.jsonPrimitive?.contentOrNull)
            })
    }

    /** The company's workplaces, creating its default one first when it has none (iOS `initializePersonnel`). */
    suspend fun ensuredWorkplaces(context: IsgWorkspaceContext, companyId: String): List<Pair<String, String>> {
        val existing = directory(context, companyId, "workplaces")
        if (existing.isNotEmpty() || !context.canOperate) return existing
        inScope(context, companyId) {
            gateway.initializePersonnel(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
                context.canOperate, companyId)
        }
        return directory(context, companyId, "workplaces")
    }

    suspend fun trainingRecords(context: IsgWorkspaceContext, companyId: String, kind: IsgWorkspaceTrainingAdvancedKind) =
        trainingAdvanced(context, companyId, kind)["rows"]!!.jsonArray.map { IsgWorkspaceAdvancedRecord.parse(it.jsonObject) }

    suspend fun personnelRecords(context: IsgWorkspaceContext, companyId: String, kind: IsgWorkspacePersonnelAdvancedKind) =
        personnelAdvanced(context, companyId, kind)["rows"]!!.jsonArray.map { IsgWorkspaceAdvancedRecord.parse(it.jsonObject) }

    suspend fun mutateTrainingAdvanced(context: IsgWorkspaceContext, mutationId: String, companyId: String, payload: JsonObject): JsonObject =
        inScope(context, companyId) {
            gateway.mutateTrainingAdvanced(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
                context.canOperate, mutationId, companyId, payload)
        }

    suspend fun mutatePersonnelAdvanced(context: IsgWorkspaceContext, mutationId: String, companyId: String, payload: JsonObject): JsonObject =
        inScope(context, companyId) {
            gateway.mutatePersonnelAdvanced(context.workspaceId, context.membership.membershipId, context.membership.permissionRevision,
                context.canOperate, mutationId, companyId, payload)
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

    companion object {
        val FILE_TYPES = mapOf("pdf" to "application/pdf", "doc" to "application/msword",
            "docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "xls" to "application/vnd.ms-excel",
            "xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "csv" to "text/csv", "jpg" to "image/jpeg",
            "jpeg" to "image/jpeg", "png" to "image/png", "webp" to "image/webp", "avif" to "image/avif", "heic" to "image/heic", "heif" to "image/heic")
        val FILE_CATEGORIES = setOf("company_logo", "risk_assessment", "emergency_plan", "training_material", "inspection_report",
            "measurement_report", "accident_record", "board_document", "handover_form", "personnel_document", "contract", "permit_form",
            "visit_evidence", "notebook_archive", "other")
        private val SAFE_ERRORS = setOf(
            "AUTH_REQUIRED", "ACCESS_DENIED", "FEATURE_UNAVAILABLE", "DOMAIN_UNAVAILABLE",
            "WORKSPACE_INACTIVE", "ASSIGNMENT_REQUIRED", "VALIDATION_ERROR", "VERSION_CONFLICT",
            "SEAT_LIMIT_REACHED", "INSUFFICIENT_CREDITS", "QUOTA_EXCEEDED", "PURCHASE_PENDING",
        )
    }
}
