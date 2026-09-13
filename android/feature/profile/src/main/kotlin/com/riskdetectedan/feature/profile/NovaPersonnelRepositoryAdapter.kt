package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.data.company.PersonnelRepository
import com.riskdetectedan.core.data.company.PersonnelServiceFailure
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import java.text.Normalizer
import java.util.UUID

/** Explicit production boundary; not installed by the offline/synthetic NOVA host. */
internal fun PersonnelRepository.novaClient(currentScope: () -> NovaPersonnelScope?): NovaPersonnelClient {
    suspend fun <T> scoped(scope: NovaPersonnelScope, block: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        if (currentScope() != scope) throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.denied)
        return try {
            val result = block(); currentCoroutineContext().ensureActive()
            if (currentScope() != scope) throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.denied)
            result
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            if (error is NovaPersonnelFailure) throw error
            val kind = when((error as? PersonnelServiceFailure)?.code) {
                "AUTH_REQUIRED", "ACCESS_DENIED", "PAID_PLAN_REQUIRED" -> NovaPersonnelFailure.Kind.denied
                "VALIDATION_ERROR", "DEPARTMENT_SCOPE_INVALID", "ASSIGNMENT_CHANGE_REQUIRED", "EMPLOYMENT_INTERVAL_INVALID" -> NovaPersonnelFailure.Kind.validation
                "VERSION_CONFLICT" -> NovaPersonnelFailure.Kind.conflict
                "DEPARTMENT_SELECTION_REQUIRED" -> NovaPersonnelFailure.Kind.selectionRequired
                else -> NovaPersonnelFailure.Kind.unavailable
            }
            throw NovaPersonnelFailure(kind)
        }
    }
    return NovaPersonnelClient(
        employees = { scope, query, archived, cursor -> scoped(scope) {
            val value = read(scope.ownerID.toString(), scope.sessionID.toString(), scope.companyID.toString(), "employees", query, archived, cursor?.toString())
            val rows = value.getValue("rows").jsonArray.map { it.jsonObject.employee(scope) }; val next = value.optionalID("next")
            pageCheck(rows.map { it.id }, next, cursor); check(archived || rows.none { it.isArchived }); NovaEmployeePage(rows, next)
        } },
        departments = { scope, query, cursor -> scoped(scope) {
            val value = read(scope.ownerID.toString(), scope.sessionID.toString(), scope.companyID.toString(), "departments", query, cursor = cursor?.toString())
            val rows = value.getValue("rows").jsonArray.map { raw -> val r = raw.jsonObject; r.checkScope(scope); NovaDepartmentRow(r.id("id"), scope.ownerID, scope.companyID, r.string("name")) }
            val next = value.optionalID("next"); pageCheck(rows.map { it.id }, next, cursor); NovaDepartmentPage(rows, next)
        } },
        detail = { scope, id -> scoped(scope) {
            val row = read(scope.ownerID.toString(), scope.sessionID.toString(), scope.companyID.toString(), "detail", id = id.toString()).employee(scope)
            check(row.id == id); row
        } },
        save = { intent -> scoped(intent.scope) {
            val r = save(intent.scope.ownerID.toString(), intent.scope.sessionID.toString(), intent.scope.companyID.toString(), personnelArguments(intent))
            r.checkScope(intent.scope)
            NovaEmployeeCommit(r.id("operation_id"), r.id("employee_id"), intent.scope.ownerID, intent.scope.companyID, r.long("version"), r.bool("is_archived"))
        } },
        pending = { scope -> scoped(scope) {
            pending(scope.ownerID.toString(), scope.sessionID.toString(), scope.companyID.toString())?.let { args ->
                val action = NovaEmployeeIntent.Action.valueOf(args.string("p_action"))
                val department = when {
                    !args.bool("p_change_department") -> NovaEmployeeDepartment.Keep
                    args["p_department"] != JsonNull -> NovaEmployeeDepartment.Existing(args.id("p_department"))
                    args["p_department_name"] != JsonNull -> NovaEmployeeDepartment.New(args.string("p_department_name"))
                    else -> NovaEmployeeDepartment.None
                }
                val intent = NovaEmployeeIntent(args.id("p_operation"), args.id("p_mutation"), scope, action, args.optionalID("p_employee"), args.long("p_expected"),
                    if (args["p_name"] == JsonNull) "" else args.string("p_name"), department)
                check(personnelArguments(intent) == args); intent
            }
        } },
    )
}

internal fun personnelArguments(intent: NovaEmployeeIntent): JsonObject {
    require(intent.expectedVersion in 0 until 9007199254740991L)
    require(if (intent.action == NovaEmployeeIntent.Action.create) intent.employeeID == null && intent.expectedVersion == 0L else intent.employeeID != null)
    var change = true; var department: UUID? = null; var departmentName: String? = null
    when(val value = intent.department) {
        NovaEmployeeDepartment.Keep -> change = false
        NovaEmployeeDepartment.None -> Unit
        is NovaEmployeeDepartment.Existing -> department = value.id
        is NovaEmployeeDepartment.New -> departmentName = personnelText(value.name, 120)
    }
    require(intent.action != NovaEmployeeIntent.Action.create || change)
    if (intent.action in setOf(NovaEmployeeIntent.Action.archive, NovaEmployeeIntent.Action.restore)) { change = false; department = null; departmentName = null }
    return buildJsonObject {
        put("p_company", intent.scope.companyID.toString()); put("p_action", intent.action.name)
        put("p_operation", intent.operationID.toString()); put("p_mutation", intent.mutationID.toString())
        put("p_employee", intent.employeeID?.toString()?.let(::JsonPrimitive) ?: JsonNull); put("p_expected", intent.expectedVersion)
        put("p_name", if (intent.action in setOf(NovaEmployeeIntent.Action.archive, NovaEmployeeIntent.Action.restore)) JsonNull else JsonPrimitive(personnelText(intent.name, 200)))
        put("p_change_department", change); put("p_department", department?.toString()?.let(::JsonPrimitive) ?: JsonNull)
        put("p_department_name", departmentName?.let(::JsonPrimitive) ?: JsonNull)
    }
}
private fun personnelText(input: String, limit: Int): String {
    val value = Normalizer.normalize(input, Normalizer.Form.NFC).replace(Regex("[ \\t\\r\\n]+"), " ").trim(' ')
    require(input.toByteArray(Charsets.UTF_8).size <= 4096 && value.toByteArray(Charsets.UTF_8).size <= limit && value.isNotBlank() && value.none { it.code < 32 || it.code == 127 || it.code == 0x200B || it.code == 0xFEFF })
    return value
}
private fun JsonObject.string(key: String) = getValue(key).jsonPrimitive.let { check(it.isString); it.content }
private fun JsonObject.id(key: String): UUID = string(key).let { raw -> UUID.fromString(raw).also { check(it.toString() == raw) } }
private fun JsonObject.optionalID(key: String): UUID? = if (getValue(key) == JsonNull) null else id(key)
private fun JsonObject.long(key: String) = getValue(key).jsonPrimitive.let { check(!it.isString); it.long.also { v -> check(v in 0..9007199254740991L) } }
private fun JsonObject.bool(key: String) = getValue(key).jsonPrimitive.let { check(!it.isString); it.boolean }
private fun JsonObject.checkScope(scope: NovaPersonnelScope) { check(id("owner_id") == scope.ownerID && id("company_id") == scope.companyID) }
private fun JsonObject.employee(scope: NovaPersonnelScope): NovaEmployeeRow {
    checkScope(scope); val dep = optionalID("department_id"); val depName = if (getValue("department_name") == JsonNull) null else string("department_name")
    check((dep == null) == (depName == null))
    return NovaEmployeeRow(id("id"), scope.ownerID, scope.companyID, string("name"), dep, depName, long("version"), bool("is_archived"))
}
private fun pageCheck(ids: List<UUID>, next: UUID?, after: UUID?) {
    val keys = ids.map { it.toString() }
    check(ids.size <= 50 && ids.distinct().size == ids.size && keys == keys.sorted() && (next == null || next == ids.lastOrNull()) && (after == null || keys.all { it > after.toString() }))
}
