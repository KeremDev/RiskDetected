package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

/** One employee's actual instruction and missing topics, independent of certificates (iOS `NovaEmployeeLearningCard.Learning`). */
@Serializable data class NovaEmployeeLearning(
    @SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String,
    @SerialName("company_id") val companyId: String, @SerialName("employee_id") val employeeId: String, val groups: List<Group>,
    @SerialName("expired_scopes") val expiredScopes: Int = 0, @SerialName("legacy_company_records") val legacyCompanyRecords: Int = 0,
) {
    @Serializable data class Group(
        val id: String, @SerialName("workplace_name") val workplaceName: String? = null, @SerialName("group_name") val groupName: String,
        val profile: String, @SerialName("required_minutes") val requiredMinutes: Int, @SerialName("received_minutes") val receivedMinutes: Int,
        @SerialName("remaining_minutes") val remainingMinutes: Int, @SerialName("group4_remaining_minutes") val group4RemainingMinutes: Int,
        @SerialName("common_remaining_minutes") val commonRemainingMinutes: Int, @SerialName("missing_topics") val missingTopics: List<Topic> = emptyList(),
        @SerialName("excluded_sessions") val excludedSessions: Int = 0, @SerialName("context_missing") val contextMissing: Boolean = false,
        val complete: Boolean, @SerialName("valid_until") val validUntil: String? = null,
    )
    @Serializable data class Topic(val code: String, val title: String)
}

class NovaEmployeeLearningException : Exception("LEARNING_UNAVAILABLE")

@Singleton
class NovaEmployeeLearningService @Inject constructor(private val transport: NovaExpertTransport) {
    /** A summary that does not answer for this owner, company and employee is refused rather than shown. */
    suspend fun load(identity: IsgWorkspaceIdentity, company: String, employee: String): NovaEmployeeLearning {
        if (transport.identityNow() != identity) throw NovaEmployeeLearningException()
        val data = try {
            transport.execute("isg_pilot_employee_learning_v1", buildJsonObject { put("p_company", company); put("p_employee", employee) })
        } catch (_: NovaExpertFailure) { currentCoroutineContext().ensureActive(); throw NovaEmployeeLearningException() }
        if (transport.identityNow() != identity) throw NovaEmployeeLearningException()
        val value = runCatching { novaJson.decodeFromJsonElement(NovaEmployeeLearning.serializer(), data) }.getOrNull() ?: throw NovaEmployeeLearningException()
        if (value.schemaVersion != 1 || !value.ownerId.sameId(identity.userId) || !value.companyId.sameId(company) || !value.employeeId.sameId(employee))
            throw NovaEmployeeLearningException()
        return value
    }
}
