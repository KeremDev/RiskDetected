package com.riskdetectedan.core.data.company

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.util.Base64
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

class PersonnelServiceFailure(val code: String): Exception(code)

/** Real SDK path; UI supplies expected scope, but only PostgreSQL grants access. */
@Singleton
class PersonnelRepository @Inject constructor(private val client: SupabaseClient, private val pendingStorage: PersonnelPendingStorage) {
    private val mutex = Mutex()
    private val json = Json { ignoreUnknownKeys = false }
    private val terminal = setOf("AUTH_REQUIRED", "ACCESS_DENIED", "PAID_PLAN_REQUIRED", "VALIDATION_ERROR", "DEPARTMENT_SCOPE_INVALID", "VERSION_CONFLICT", "DEPARTMENT_SELECTION_REQUIRED", "ASSIGNMENT_CHANGE_REQUIRED", "EMPLOYMENT_INTERVAL_INVALID")
    private val directoryTerminal = terminal + setOf("EMPLOYER_SCOPE_INVALID", "ASSIGNMENT_SCOPE_INVALID", "CONTEXT_SCOPE_INVALID", "TIMEZONE_INVALID", "IMMUTABLE_SCOPE", "HIERARCHY_CYCLE", "ASSIGNMENT_IMMUTABLE", "CONTEXT_IMMUTABLE", "EMPLOYMENT_INTERVAL_INVALID", "ASSIGNMENT_CHANGE_REQUIRED")
    private fun current(owner: String, session: String): Boolean {
        val active = client.auth.currentSessionOrNull() ?: return false
        if (client.auth.currentUserOrNull()?.id != owner) return false
        return runCatching {
            val body = json.parseToJsonElement(String(Base64.getUrlDecoder().decode(active.accessToken.split('.')[1]), Charsets.UTF_8)).jsonObject
            body["session_id"]?.jsonPrimitive?.content == session
        }.getOrDefault(false)
    }
    private suspend fun check(owner: String, session: String) {
        currentCoroutineContext().ensureActive()
        if (!current(owner, session)) throw PersonnelServiceFailure("AUTH_REQUIRED")
    }
    private fun account(owner: String, company: String): String {
        require(UUID.fromString(owner).toString() == owner && UUID.fromString(company).toString() == company)
        return "$owner:$company"
    }
    private suspend fun invoke(function: String, args: JsonObject): JsonObject = try {
        val raw = client.postgrest.rpc(function, args).data
        require(raw.toByteArray(Charsets.UTF_8).size <= 262144)
        json.parseToJsonElement(raw).jsonObject
    } catch (error: Exception) {
        currentCoroutineContext().ensureActive()
        val response = when(error) { is RestException -> error.response; is ResponseException -> error.response; else -> null }
        val body = response?.let { runCatching { json.parseToJsonElement(it.bodyAsText()).jsonObject }.getOrNull() }
        val state = body?.get("code")?.jsonPrimitive?.content
        val message = body?.get("message")?.jsonPrimitive?.content
        if (state in setOf("P0001", "28000") && message in directoryTerminal) throw PersonnelServiceFailure(message!!)
        if (state in setOf("23503", "23505", "23514", "23P01", "22007", "22008", "22P02")) throw PersonnelServiceFailure("VALIDATION_ERROR")
        throw PersonnelServiceFailure("UNAVAILABLE") // No payload/token or server diagnostics in UI/logs.
    }
    suspend fun read(owner: String, session: String, company: String, kind: String, query: String = "", archived: Boolean = false, cursor: String? = null, id: String? = null): JsonObject {
        check(owner, session); account(owner, company)
        require(kind in setOf("employees", "departments", "detail") && query.toByteArray(Charsets.UTF_8).size <= 200)
        val result = invoke("isg_personnel_read_v1", buildJsonObject {
            put("p_company", company); put("p_kind", kind); put("p_query", query); put("p_archived", archived)
            put("p_after", cursor?.let(::JsonPrimitive) ?: JsonNull); put("p_id", id?.let(::JsonPrimitive) ?: JsonNull)
        })
        check(owner, session); return result
    }
    private fun load(owner: String, company: String): JsonObject? {
        val raw = pendingStorage.read(account(owner, company)) ?: return null
        val envelope = json.parseToJsonElement(raw).jsonObject
        check(envelope["schema"]?.jsonPrimitive?.int == 1 && envelope["owner"]?.jsonPrimitive?.content == owner)
        val args = envelope["args"]!!.jsonObject
        check(args["p_company"]?.jsonPrimitive?.content == company)
        return args
    }
    suspend fun pending(owner: String, session: String, company: String): JsonObject? = mutex.withLock {
        check(owner, session); load(owner, company)
    }
    suspend fun directoryRead(owner: String, session: String, company: String, kind: String, parent: String?, cursor: String?, archived: Boolean): JsonObject {
        check(owner, session); account(owner, company)
        require(kind in directoryKinds)
        val result = invoke("isg_directory_read_v1", buildJsonObject {
            put("p_company", company); put("p_kind", kind); put("p_parent", parent?.let(::JsonPrimitive) ?: JsonNull)
            put("p_after", cursor?.let(::JsonPrimitive) ?: JsonNull); put("p_archived", archived)
        })
        check(owner, session); return result
    }
    private fun loadDirectory(owner: String, company: String): JsonObject? {
        val raw = pendingStorage.read("directory:" + account(owner, company)) ?: return null
        val envelope = json.parseToJsonElement(raw).jsonObject
        check(envelope["schema"] == JsonPrimitive(1) && envelope["owner"] == JsonPrimitive(owner))
        val args = envelope.getValue("args").jsonObject
        check(args["p_company"] == JsonPrimitive(company)); return args
    }
    suspend fun directoryPending(owner: String, session: String, company: String): JsonObject? = mutex.withLock {
        check(owner, session); loadDirectory(owner, company)
    }
    suspend fun directorySave(owner: String, session: String, company: String, args: JsonObject): JsonObject = mutex.withLock {
        check(owner, session)
        require(args.keys == setOf("p_company", "p_kind", "p_operation", "p_mutation", "p_id", "p_expected", "p_body"))
        require(args["p_company"] == JsonPrimitive(company))
        val kind = args.getValue("p_kind").jsonPrimitive.content
        require(kind in directoryKinds)
        val expected = args.getValue("p_expected").jsonPrimitive.long
        require(expected in 0 until 9007199254740991L && args["p_expected"] == JsonPrimitive(expected))
        val old = loadDirectory(owner, company)
        if (old != null && old != args) throw PersonnelServiceFailure("UNAVAILABLE")
        val key = "directory:" + account(owner, company)
        pendingStorage.write(key, buildJsonObject { put("schema", 1); put("owner", owner); put("args", args) }.toString())
        try {
            val r = invoke("isg_directory_mutate_v1", args); check(owner, session)
            check(r["schema_version"] == JsonPrimitive(1) && r["owner_id"] == JsonPrimitive(owner) && r["company_id"] == JsonPrimitive(company))
            check(r["operation_id"] == args["p_operation"] && r["kind"] == args["p_kind"])
            val id = r.getValue("entity_id").jsonPrimitive
            check(id.isString && UUID.fromString(id.content).toString() == id.content)
            check(args["p_id"] == JsonNull || args["p_id"] == id)
            val version = if (args["p_id"] == JsonNull && kind in setOf("workplaces", "departments", "jobs", "contractors", "engagements")) 0 else expected + 1
            check(r["version"] == JsonPrimitive(version))
            pendingStorage.remove(key); r
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            if (current(owner, session) && error is PersonnelServiceFailure && error.code in directoryTerminal) pendingStorage.remove(key)
            throw error
        }
    }
    private val directoryKinds = setOf("workplaces", "departments", "jobs", "contractors", "engagements", "contexts", "assignments", "employers")
    suspend fun save(owner: String, session: String, company: String, args: JsonObject): JsonObject = mutex.withLock {
        check(owner, session)
        require(args.keys == setOf("p_company", "p_action", "p_operation", "p_mutation", "p_employee", "p_expected", "p_name", "p_change_department", "p_department", "p_department_name"))
        require(args["p_company"]?.jsonPrimitive?.content == company)
        val old = load(owner, company)
        if (old != null && old != args) throw PersonnelServiceFailure("UNAVAILABLE")
        pendingStorage.write(account(owner, company), buildJsonObject { put("schema", 1); put("owner", owner); put("args", args) }.toString())
        try {
            val result = invoke("isg_personnel_mutate_v1", args); check(owner, session)
            val action = args["p_action"]!!.jsonPrimitive.content
            check(result["schema_version"] == JsonPrimitive(1) && result["owner_id"] == JsonPrimitive(owner) && result["company_id"] == JsonPrimitive(company))
            check(result["operation_id"] == args["p_operation"])
            val resultID = result["employee_id"]!!.jsonPrimitive.content
            check(UUID.fromString(resultID).toString() == resultID)
            check(args["p_employee"] == JsonNull || result["employee_id"] == args["p_employee"])
            val expected = if (action == "create") 0L else args["p_expected"]!!.jsonPrimitive.long + 1
            check(result["version"] == JsonPrimitive(expected) && result["is_archived"] == JsonPrimitive(action == "archive"))
            pendingStorage.remove(account(owner, company)); result
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            if (current(owner, session) && error is PersonnelServiceFailure && error.code in terminal) pendingStorage.remove(account(owner, company))
            throw error
        }
    }
}
