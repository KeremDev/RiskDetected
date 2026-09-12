package com.riskdetectedan.core.data.isg

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

/** Additive strict transport. No old API, network loop or UI is wired here. */
data class IsgMutationOutcome(val operationId: String, val requestId: String, val supportId: String,
    val outcome: String, val code: String?, val version: Long?, val currentVersion: Long?,
    val projection: String?, val retryAfterSeconds: Long?) {
    companion object {
        private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        private val codes = mapOf("AUTH_REQUIRED" to 401,"COMPANY_ACCESS_DENIED" to 403,"CAPABILITY_DISABLED" to 403,
            "CROSS_COMPANY_REFERENCE" to 403,"VERSION_CONFLICT" to 409,"VALIDATION_FAILED" to 422,"RULE_REVIEW_REQUIRED" to 409,
            "DOCUMENT_NOT_READY" to 409,"QUOTA_EXCEEDED" to 409,"IDEMPOTENCY_CONFLICT" to 409,"SCAN_PENDING" to 423,"UNSUPPORTED_FORMAT" to 415)
        private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        private fun JsonObject.number(key: String): Long? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.let {
            it.longOrNull ?: it.content.toDoubleOrNull()?.takeIf { n -> n.isFinite() && n % 1.0 == 0.0 && n >= 0 && n <= 9007199254740991.0 }?.toLong()
        }
        fun parse(status: Int, input: JsonElement): IsgMutationOutcome? {
            val obj = input as? JsonObject ?: return null
            if (obj.number("schema_version") != 1L) return null
            val operation = obj.text("operation_id")?.takeIf(uuid::matches) ?: return null
            val request = obj.text("request_id")?.takeIf(uuid::matches) ?: return null
            val support = obj.text("support_id")?.takeIf { Regex("^ISG-[A-F0-9]{12}$").matches(it) } ?: return null
            val outcome = obj.text("outcome") ?: return null
            val fields = mutableSetOf("schema_version","operation_id","request_id","support_id","outcome")
            var code: String? = null; var version: Long? = null; var current: Long? = null
            var projection: String? = null; var delay: Long? = null
            when (outcome) {
                "committed" -> {
                    if (status != 200) return null
                    version = obj.number("version")?.takeIf { it in 0..9007199254740991L } ?: return null
                    projection = obj.text("projection")?.takeIf { it in listOf("ready","pending","failed") } ?: return null
                    fields.addAll(listOf("version","projection"))
                }
                "pending", "indeterminate" -> {
                    if (status != (if (outcome == "pending") 202 else 503)) return null
                    code = obj.text("code")?.takeIf { it == (if (outcome == "pending") "JOB_PENDING" else "RETRYABLE_FAILURE") } ?: return null
                    delay = obj.number("retry_after_seconds")?.takeIf { it in 1..300L } ?: return null
                    fields.addAll(listOf("code","retry_after_seconds"))
                }
                "rejected" -> {
                    code = obj.text("code")?.takeIf { codes[it] == status } ?: return null
                    fields.add("code")
                    if (code == "VERSION_CONFLICT") {
                        current = obj.number("current_version")?.takeIf { it in 0..9007199254740991L } ?: return null
                        fields.add("current_version")
                    }
                }
                else -> return null
            }
            if (obj.keys != fields) return null
            return IsgMutationOutcome(operation,request,support,outcome,code,version,current,projection,delay)
        }
    }
}

enum class IsgMutationPhase { prepared, submitting, reconciling, committed, blocked, detached }
enum class IsgMutationEvent { submit, transport_loss, committed, pending, indeterminate, rejected, account_changed }
data class IsgMutationTransition(val phase: IsgMutationPhase, val effect: String) {
    companion object {
        /** sameContext is computed by a coordinator from operation ID AND auth-session epoch. */
        fun next(phase: IsgMutationPhase, event: IsgMutationEvent, sameContext: Boolean): IsgMutationTransition {
            if (!sameContext || phase == IsgMutationPhase.detached) return IsgMutationTransition(phase,"none")
            if (event == IsgMutationEvent.account_changed) return IsgMutationTransition(IsgMutationPhase.detached,"detach")
            if (phase == IsgMutationPhase.prepared && event == IsgMutationEvent.submit) return IsgMutationTransition(IsgMutationPhase.submitting,"submit_same_key")
            if (phase != IsgMutationPhase.submitting && phase != IsgMutationPhase.reconciling) return IsgMutationTransition(phase,"none")
            return when (event) {
                IsgMutationEvent.committed -> IsgMutationTransition(IsgMutationPhase.committed,"show_committed")
                IsgMutationEvent.rejected -> IsgMutationTransition(IsgMutationPhase.blocked,"show_blocked")
                IsgMutationEvent.transport_loss, IsgMutationEvent.pending, IsgMutationEvent.indeterminate -> IsgMutationTransition(IsgMutationPhase.reconciling,"reconcile_same_operation")
                else -> IsgMutationTransition(phase,"none")
            }
        }
    }
}
