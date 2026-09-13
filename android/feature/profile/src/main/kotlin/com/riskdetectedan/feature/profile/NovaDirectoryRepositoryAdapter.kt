package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.data.company.PersonnelRepository
import com.riskdetectedan.core.data.company.PersonnelServiceFailure
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import java.util.UUID

internal fun PersonnelRepository.novaDirectoryClient(currentScope: () -> NovaPersonnelScope?): NovaDirectoryClient {
    suspend fun <T> scoped(scope: NovaPersonnelScope, block: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        if (currentScope() != scope) throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.denied)
        try {
            val result = block(); currentCoroutineContext().ensureActive()
            if (currentScope() != scope) throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.denied)
            return result
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            if (error is NovaPersonnelFailure) throw error
            val code = (error as? PersonnelServiceFailure)?.code
            throw NovaPersonnelFailure(when(code) {
                "VERSION_CONFLICT" -> NovaPersonnelFailure.Kind.conflict
                "AUTH_REQUIRED", "ACCESS_DENIED", "PAID_PLAN_REQUIRED" -> NovaPersonnelFailure.Kind.denied
                null, "UNAVAILABLE", "FEATURE_UNAVAILABLE", "IDEMPOTENCY_CONFLICT" -> NovaPersonnelFailure.Kind.unavailable
                else -> NovaPersonnelFailure.Kind.validation
            })
        }
    }
    return NovaDirectoryClient(
        read = { scope, kind, parent, after, archived -> scoped(scope) {
            val r = directoryRead(scope.ownerID.toString(), scope.sessionID.toString(), scope.companyID.toString(), kind.name, parent?.toString(), after?.toString(), archived)
            val rows = r.getValue("rows").jsonArray.map { element ->
                val row = element.jsonObject
                check(row["owner_id"] == JsonPrimitive(scope.ownerID.toString()) && row["company_id"] == JsonPrimitive(scope.companyID.toString()))
                NovaDirectoryRow(row.directoryID("id")!!, row.mapValues { it.value.directoryValue() })
            }
            val ids = rows.map { it.id.toString() }; val next = r.directoryID("next")
            check(ids.size <= 50 && ids.distinct().size == ids.size && ids == ids.sorted() && (next == null || next == rows.lastOrNull()?.id))
            check(after == null || ids.all { it > after.toString() })
            val version = r.getValue("parent_version").let { if (it == JsonNull) null else (it.directoryValue() as NovaDirectoryValue.Number).value }
            NovaDirectoryPage(rows, next, version)
        } },
        save = { intent -> scoped(intent.scope) {
            val r = directorySave(intent.scope.ownerID.toString(), intent.scope.sessionID.toString(), intent.scope.companyID.toString(), intent.directoryArgs())
            NovaDirectoryCommit(r.directoryID("operation_id")!!, r.directoryID("entity_id")!!, (r.getValue("version").directoryValue() as NovaDirectoryValue.Number).value)
        } },
        pending = { scope -> scoped(scope) {
            directoryPending(scope.ownerID.toString(), scope.sessionID.toString(), scope.companyID.toString())?.let { args ->
                val intent = NovaDirectoryIntent(scope, NovaDirectoryKind.valueOf(args.getValue("p_kind").jsonPrimitive.content), args.directoryID("p_operation")!!,
                    args.directoryID("p_mutation")!!, args.directoryID("p_id"), (args.getValue("p_expected").directoryValue() as NovaDirectoryValue.Number).value,
                    args.getValue("p_body").jsonObject.mapValues { it.value.directoryValue() })
                check(intent.directoryArgs() == args); intent
            }
        } },
    )
}
internal fun NovaDirectoryIntent.directoryArgs() = buildJsonObject {
    require(expectedVersion in 0 until 9007199254740991L && body.size <= 12)
    put("p_company", scope.companyID.toString()); put("p_kind", kind.name); put("p_operation", operationID.toString()); put("p_mutation", mutationID.toString())
    put("p_id", entityID?.toString()?.let(::JsonPrimitive) ?: JsonNull); put("p_expected", expectedVersion)
    put("p_body", JsonObject(body.mapValues { (_, value) -> when(value) {
        NovaDirectoryValue.Null -> JsonNull
        is NovaDirectoryValue.Text -> JsonPrimitive(value.value)
        is NovaDirectoryValue.Number -> JsonPrimitive(value.value)
        is NovaDirectoryValue.Flag -> JsonPrimitive(value.value)
    } }))
}
private fun JsonElement.directoryValue(): NovaDirectoryValue {
    if (this == JsonNull) return NovaDirectoryValue.Null
    val p = jsonPrimitive
    return when { p.isString -> NovaDirectoryValue.Text(p.content); p.booleanOrNull != null -> NovaDirectoryValue.Flag(p.boolean); else -> NovaDirectoryValue.Number(p.long) }
}
private fun JsonObject.directoryID(key: String): UUID? {
    val p = getValue(key); if (p == JsonNull) return null
    check(p.jsonPrimitive.isString)
    val id = UUID.fromString(p.jsonPrimitive.content); check(id.toString() == p.jsonPrimitive.content); return id
}
