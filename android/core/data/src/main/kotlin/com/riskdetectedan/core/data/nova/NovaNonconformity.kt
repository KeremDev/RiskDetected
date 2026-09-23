package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.text.Normalizer
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** One company the expert is working in; the server re-checks it on every call. */
data class NovaCompanyScope(val identity: IsgWorkspaceIdentity, val companyId: String)

/** The four severities the server accepts; an unreadable legacy band is never mapped to one. */
enum class NovaNonconformitySeverity { low, medium, high, critical }

enum class NovaNonconformityState { draft, open, assigned, in_progress, pending_verification, closed, reopened, cancelled;
    companion object { fun of(value: String) = entries.firstOrNull { it.name == value } }
}

/** An improvement suggestion travels the same lifecycle but is never counted as a nonconformity. */
enum class NovaNonconformityRecordKind { nonconformity, improvement;
    companion object { fun of(value: String?) = entries.firstOrNull { it.name == value } }
}

enum class NovaRiskMethod(val wire: String) {
    fineKinney("fine_kinney"), matrix5x5("matrix_5x5");
    /** The product's name for the method (iOS `RiskMethod.label`). */
    val label: String get() = if (this == fineKinney) "Fine-Kinney" else "5×5 L-Tipi"
    /** The short code the analysis aggregates use (iOS `RiskMethod.rawValue`). */
    val code: String get() = if (this == fineKinney) "fk" else "m5"
    companion object {
        fun of(wire: String?) = entries.firstOrNull { it.wire == wire }
        val probabilityScale = listOf(0.2, 0.5, 1.0, 3.0, 6.0, 10.0)
        val frequencyScale = listOf(0.5, 1.0, 2.0, 3.0, 6.0, 10.0)
        val severityScale = listOf(1.0, 3.0, 7.0, 15.0, 40.0, 100.0)
        val matrixScale = listOf(1, 2, 3, 4, 5)
    }
}

/** What the expert has entered in the scoring step (iOS `NovaRiskScoreInput`). */
data class NovaRiskScoreInput(
    val method: NovaRiskMethod? = null, val probability: Double? = null, val frequency: Double? = null,
    val severity: Double? = null, val matrixProbability: Int? = null, val matrixSeverity: Int? = null,
) {
    /** Complete means the chosen method has all its inputs; a half-filled method is not a score. */
    val isComplete: Boolean get() = when (method) {
        null -> false
        NovaRiskMethod.fineKinney -> probability != null && frequency != null && severity != null
        NovaRiskMethod.matrix5x5 -> matrixProbability != null && matrixSeverity != null
    }
    val isEmpty: Boolean get() = this == NovaRiskScoreInput()
    val score: Double? get() = if (!isComplete) null else when (method) {
        NovaRiskMethod.fineKinney -> probability!! * frequency!! * severity!!
        NovaRiskMethod.matrix5x5 -> (matrixProbability!! * matrixSeverity!!).toDouble()
        null -> null
    }
    /** The preview band; the stored band is the server's generated column. */
    val band: NovaNonconformitySeverity? get() {
        val value = score ?: return null
        return when (method) {
            NovaRiskMethod.fineKinney -> when { value <= 70 -> NovaNonconformitySeverity.low; value <= 200 -> NovaNonconformitySeverity.medium
                value <= 400 -> NovaNonconformitySeverity.high; else -> NovaNonconformitySeverity.critical }
            NovaRiskMethod.matrix5x5 -> when { value <= 4 -> NovaNonconformitySeverity.low; value <= 9 -> NovaNonconformitySeverity.medium
                value <= 19 -> NovaNonconformitySeverity.high; else -> NovaNonconformitySeverity.critical }
            null -> null
        }
    }
    /** Switching method drops the other method's inputs. */
    fun select(value: NovaRiskMethod?): NovaRiskScoreInput = if (method == value) this else NovaRiskScoreInput(method = value)
}

@Serializable
data class NovaCorrectiveAction(val id: String, val description: String, val assignee: String? = null,
                                @SerialName("due_on") val dueOn: String? = null, val state: String)

@Serializable
data class NovaVerificationRecord(val id: String, val outcome: String, @SerialName("verified_on") val verifiedOn: String)

@Serializable
data class NovaEvidenceDownload(val bucket: String, val path: String)

@Serializable
data class NovaNonconformityDetail(
    val description: String? = null, @SerialName("control_measure") val controlMeasure: String? = null,
    @SerialName("legislation_ref") val legislationRef: String? = null,
    @SerialName("responsible_contact") val responsibleContact: String? = null,
    @SerialName("risk_method") val riskMethod: String? = null,
    @SerialName("fk_probability") val fkProbability: Double? = null, @SerialName("fk_frequency") val fkFrequency: Double? = null,
    @SerialName("fk_severity") val fkSeverity: Double? = null, @SerialName("m5_probability") val m5Probability: Int? = null,
    @SerialName("m5_severity") val m5Severity: Int? = null, @SerialName("risk_score") val riskScore: Double? = null,
    @SerialName("risk_band") val riskBand: String? = null,
) {
    val scoreInput: NovaRiskScoreInput get() = NovaRiskScoreInput(NovaRiskMethod.of(riskMethod), fkProbability, fkFrequency,
        fkSeverity, m5Probability, m5Severity)
}

@Serializable
data class NovaNonconformityRow(
    val id: String,
    @SerialName("workplace_id") val workplaceId: String,
    val title: String,
    val severity: String,
    val state: String,
    val version: Long,
    @SerialName("opened_on") val openedOn: String,
    @SerialName("due_on") val dueOn: String? = null,
    @SerialName("source_kind") val sourceKind: String,
    @SerialName("source_ref") val sourceRef: String? = null,
    @SerialName("record_kind") val recordKind: String? = null,
    @SerialName("risk_band") val riskBand: String? = null,
    @SerialName("closed_on") val closedOn: String? = null,
    @SerialName("assignee_contact") val assigneeContact: String? = null,
    val detail: NovaNonconformityDetail? = null,
    val actions: List<NovaCorrectiveAction>? = null,
    val verifications: List<NovaVerificationRecord>? = null,
    @SerialName("evidence_asset_ids") val evidenceAssetIds: List<String>? = null,
    @SerialName("evidence_downloads") val evidenceDownloads: List<NovaEvidenceDownload>? = null,
) {
    val cameFromFinding: Boolean get() = sourceKind == "legacy_finding" || sourceKind == "analysis_finding"
    val cameFromExpertItem: Boolean get() = sourceKind == "legacy_expert_item" || sourceKind == "analysis_expert_item"
    val kind: NovaNonconformityRecordKind get() = NovaNonconformityRecordKind.of(recordKind) ?: NovaNonconformityRecordKind.nonconformity
    val sourceTitle: String get() = when (sourceKind) {
        "checklist" -> "Kontrol listesinden"
        "legacy_finding", "analysis_finding" -> "Analizden"
        "legacy_expert_item", "analysis_expert_item" -> "Uzman görüşünden"
        "risk_version" -> "Risk analizinden"
        "manual" -> "Elle eklendi"
        else -> "Sistem kaydı"
    }
    val sourceSymbol: String get() = when (sourceKind) {
        "checklist" -> "checklist"
        "legacy_finding", "analysis_finding" -> "sparkles"
        "legacy_expert_item", "analysis_expert_item" -> "person.text.rectangle"
        "risk_version" -> "exclamationmark.shield"
        else -> "square.and.pencil"
    }
}

@Serializable
data class NovaNonconformityWorkplace(val id: String, val name: String, @SerialName("needs_review") val needsReview: Boolean)

/** A company choice offered by the analysis and nonconformity pickers. */
data class NovaCompanyOption(val id: String, val name: String, val detail: String, val sector: String?, val hazardClass: String? = null)

enum class NovaNonconformityFailure { denied, validation, conflict, unavailable, severityUnknown, payloadRejected, riskInputIncomplete }

class NovaNonconformityException(val failure: NovaNonconformityFailure) : Exception(failure.name)

/** One allowed move of the state machine; the same sixteen edges are server data. */
data class NovaNonconformityEdge(val from: NovaNonconformityState, val to: NovaNonconformityState,
                                 val requiresReason: Boolean, val requiresAssignee: Boolean, val requiresVerification: Boolean) {
    val id: String get() = "${from.name}>${to.name}"
}

object NovaNonconformityMachine {
    private fun e(from: NovaNonconformityState, to: NovaNonconformityState, reason: Boolean = false, assignee: Boolean = false,
                  verification: Boolean = false) = NovaNonconformityEdge(from, to, reason, assignee, verification)
    val edges = listOf(
        e(NovaNonconformityState.draft, NovaNonconformityState.open), e(NovaNonconformityState.draft, NovaNonconformityState.cancelled, reason = true),
        e(NovaNonconformityState.open, NovaNonconformityState.assigned, assignee = true), e(NovaNonconformityState.open, NovaNonconformityState.cancelled, reason = true),
        e(NovaNonconformityState.assigned, NovaNonconformityState.in_progress), e(NovaNonconformityState.assigned, NovaNonconformityState.open, reason = true), e(NovaNonconformityState.assigned, NovaNonconformityState.cancelled, reason = true),
        e(NovaNonconformityState.in_progress, NovaNonconformityState.pending_verification), e(NovaNonconformityState.in_progress, NovaNonconformityState.assigned, reason = true, assignee = true),
        e(NovaNonconformityState.in_progress, NovaNonconformityState.cancelled, reason = true),
        e(NovaNonconformityState.pending_verification, NovaNonconformityState.closed, verification = true), e(NovaNonconformityState.pending_verification, NovaNonconformityState.in_progress, reason = true),
        e(NovaNonconformityState.closed, NovaNonconformityState.reopened, reason = true),
        e(NovaNonconformityState.reopened, NovaNonconformityState.assigned, assignee = true), e(NovaNonconformityState.reopened, NovaNonconformityState.in_progress), e(NovaNonconformityState.reopened, NovaNonconformityState.cancelled, reason = true),
    )
    fun moves(from: NovaNonconformityState) = edges.filter { it.from == from }
    fun isTerminal(state: NovaNonconformityState) = moves(state).isEmpty()
}

/** Turkish-aware folding for search, as iOS `NovaSectorMatch.normalize`. */
fun novaFold(value: String): String = Normalizer.normalize(value.lowercase(Locale.forLanguageTag("tr-TR")), Normalizer.Form.NFD)
    .replace(Regex("\\p{Mn}+"), "").replace('ı', 'i')

data class NovaNonconformityFilter(val companyId: String? = null, val state: NovaNonconformityState? = null,
                                   val kind: NovaNonconformityRecordKind? = null, val query: String = "",
                                   val overdueOnly: Boolean = false) {
    val isEmpty: Boolean get() = companyId == null && state == null && kind == null && !overdueOnly && query.isBlank()
}

/** One row of the cross-company board: the record plus its company. */
data class NovaNonconformityEntry(val row: NovaNonconformityRow, val companyId: String, val companyName: String,
                                  val workplaceName: String?) {
    val id: String get() = row.id
    fun isOverdue(today: String): Boolean {
        val due = row.dueOn ?: return false
        // ISO day strings compare correctly as text; no time zone can shift the answer.
        return row.state !in setOf("closed", "cancelled") && due < today
    }
    fun matches(filter: NovaNonconformityFilter, today: String): Boolean {
        if (filter.companyId != null && filter.companyId != companyId) return false
        if (filter.state != null && filter.state.name != row.state) return false
        if (filter.kind != null && filter.kind != row.kind) return false
        if (filter.overdueOnly && !isOverdue(today)) return false
        val needle = filter.query.trim()
        if (needle.isEmpty()) return true
        val folded = novaFold(needle)
        return listOf(row.title, companyName, workplaceName.orEmpty()).any { novaFold(it).contains(folded) }
    }
}

enum class NovaManualStep { photo, company, hazard, scoring, legislation, responsible }

/** One hand-entered record and which of its steps are finished (iOS `NovaManualDraft`). */
data class NovaManualDraft(
    val photoCount: Int = 0, val evidenceAssetIds: List<String> = emptyList(), val companyId: String? = null,
    val workplaceId: String? = null, val title: String = "", val hazardDescription: String = "",
    val controlMeasure: String = "", val severity: NovaNonconformitySeverity = NovaNonconformitySeverity.medium,
    val recordKind: NovaNonconformityRecordKind = NovaNonconformityRecordKind.nonconformity,
    val score: NovaRiskScoreInput = NovaRiskScoreInput(), val legislation: String = "", val responsible: String = "",
    val dueOn: String? = null,
) {
    fun isComplete(step: NovaManualStep): Boolean = when (step) {
        NovaManualStep.photo -> photoCount > 0
        NovaManualStep.company -> companyId != null && workplaceId != null
        NovaManualStep.hazard -> title.isNotBlank() && hazardDescription.isNotBlank() && controlMeasure.isNotBlank()
        NovaManualStep.scoring -> score.isComplete
        NovaManualStep.legislation -> legislation.isNotBlank()
        NovaManualStep.responsible -> responsible.isNotBlank()
    }
    val canSave: Boolean get() = isComplete(NovaManualStep.company) && isComplete(NovaManualStep.hazard) &&
        (score.isEmpty || score.isComplete)
    val completedCount: Int get() = NovaManualStep.entries.count(::isComplete)
    val progress: Float get() = completedCount.toFloat() / NovaManualStep.entries.size
    fun nextIncomplete(after: NovaManualStep): NovaManualStep? =
        NovaManualStep.entries.drop(after.ordinal + 1).firstOrNull { !isComplete(it) }
}

/** What an open request carries (iOS `NovaNonconformityIntent`). */
data class NovaNonconformityIntent(
    val origin: Origin, val workplaceId: String, val title: String,
    val severity: NovaNonconformitySeverity? = null, val riskBand: String? = null, val findingId: String? = null,
    val sourceMethod: NovaRiskMethod? = null, val expertItemId: String? = null,
    val recordKind: NovaNonconformityRecordKind = NovaNonconformityRecordKind.nonconformity,
    val dueOn: String? = null, val assignee: String? = null, val hazardDescription: String? = null,
    val controlMeasure: String? = null, val legislation: String? = null, val responsible: String? = null,
    val score: NovaRiskScoreInput = NovaRiskScoreInput(), val evidenceAssetIds: List<String> = emptyList(),
) {
    enum class Origin(val action: String) { manual("open_manual"), finding("open_from_finding"),
        expertItem("open_from_expert_item"), detailed("open_detailed") }
}

data class NovaNonconformityDetailDraft(val description: String = "", val measure: String = "", val legislation: String = "",
                                        val responsible: String = "", val score: NovaRiskScoreInput = NovaRiskScoreInput()) {
    companion object {
        fun of(detail: NovaNonconformityDetail?) = NovaNonconformityDetailDraft(detail?.description.orEmpty(),
            detail?.controlMeasure.orEmpty(), detail?.legislationRef.orEmpty(), detail?.responsibleContact.orEmpty(),
            detail?.scoreInput ?: NovaRiskScoreInput())
    }
}

/** The nonconformity boundary (iOS `NovaNonconformityService`), through the expert transport. */
@Singleton
class NovaNonconformityService @Inject constructor(private val transport: NovaExpertTransport,
                                                   private val overview: NovaOverviewService) {
    @Serializable private data class ListEnvelope(val rows: List<NovaNonconformityRow>)
    @Serializable private data class WorkplaceEnvelope(val rows: List<NovaNonconformityWorkplace>)
    @Serializable private data class DetailEnvelope(val row: NovaNonconformityRow)
    @Serializable private data class Outcome(val replayed: Boolean? = null)
    @Serializable private data class MutationEnvelope(val row: NovaNonconformityRow, val replayed: Boolean, val outcome: Outcome? = null)

    data class OpenResult(val row: NovaNonconformityRow, val alreadyOpen: Boolean)

    private fun check(scope: NovaCompanyScope) {
        if (transport.identityNow() != scope.identity) throw NovaNonconformityException(NovaNonconformityFailure.denied)
    }

    private suspend fun call(function: String, args: JsonObject): JsonElement = try {
        transport.execute(function, args)
    } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive()
        throw NovaNonconformityException(when {
            failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaNonconformityFailure.unavailable
            failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED", "PAID_PLAN_REQUIRED") -> NovaNonconformityFailure.denied
            failure.code == "SEVERITY_UNKNOWN" -> NovaNonconformityFailure.severityUnknown
            failure.code == "PAYLOAD_NOT_ALLOWED" -> NovaNonconformityFailure.payloadRejected
            failure.code == "RISK_INPUT_INCOMPLETE" -> NovaNonconformityFailure.riskInputIncomplete
            failure.code in setOf("VALIDATION_ERROR", "SOURCE_REFERENCE_REQUIRED") -> NovaNonconformityFailure.validation
            failure.code in setOf("VERSION_CONFLICT", "IDEMPOTENCY_CONFLICT", "STATE_TRANSITION_INVALID") -> NovaNonconformityFailure.conflict
            else -> NovaNonconformityFailure.unavailable
        })
    }

    private fun <T> JsonElement.decode(serializer: kotlinx.serialization.KSerializer<T>): T = try {
        novaJson.decodeFromJsonElement(serializer, this)
    } catch (_: Exception) { throw NovaNonconformityException(NovaNonconformityFailure.unavailable) }

    private fun readArgs(company: String, kind: String, query: String? = null, state: String? = null, id: String? = null) =
        buildJsonObject {
            put("p_company", company); put("p_kind", kind); putId("p_query", query); putId("p_state", state)
            put("p_after", JsonNull); putId("p_id", id)
        }

    suspend fun list(scope: NovaCompanyScope, state: NovaNonconformityState? = null, query: String = ""): List<NovaNonconformityRow> {
        check(scope)
        val rows = call("isg_nonconformity_read_v1", readArgs(scope.companyId, "list", query, state?.name))
            .decode(ListEnvelope.serializer()).rows
        check(scope); return rows
    }

    suspend fun workplaces(scope: NovaCompanyScope): List<NovaNonconformityWorkplace> {
        check(scope)
        val rows = call("isg_nonconformity_read_v1", readArgs(scope.companyId, "workplaces")).decode(WorkplaceEnvelope.serializer()).rows
        check(scope); return rows
    }

    /** Legacy companies can lack their default workplace; filing repairs it server side. */
    suspend fun filingWorkplaces(scope: NovaCompanyScope): List<NovaNonconformityWorkplace> {
        val existing = workplaces(scope)
        if (existing.isNotEmpty()) return existing
        check(scope)
        call("isg_analysis_filing_workplace_v1", buildJsonObject { put("p_company", scope.companyId) })
        val repaired = workplaces(scope)
        if (repaired.isEmpty()) throw NovaNonconformityException(NovaNonconformityFailure.unavailable)
        return repaired
    }

    private fun mutation(scope: NovaCompanyScope, action: String, payload: JsonObject, operation: String, mutation: String) =
        buildJsonObject {
            put("p_company", scope.companyId); put("p_action", action); put("p_operation", operation)
            put("p_mutation", mutation); put("p_payload", payload)
        }

    /** Operation and mutation ids travel with the request, so a retry returns the first answer. */
    suspend fun open(scope: NovaCompanyScope, intent: NovaNonconformityIntent, operationId: String = UUID.randomUUID().toString(),
                     mutationId: String = UUID.randomUUID().toString()): OpenResult {
        check(scope)
        val assignee = intent.assignee?.trim().orEmpty()
        val payload = buildJsonObject {
            put("workplace_id", intent.workplaceId); put("title", intent.title)
            intent.severity?.let { put("severity", it.name) }
            intent.dueOn?.let { put("due_on", it) }
            when (intent.origin) {
                NovaNonconformityIntent.Origin.manual -> if (assignee.isNotEmpty()) put("assignee", assignee)
                NovaNonconformityIntent.Origin.finding -> {
                    put("finding_id", intent.findingId ?: throw NovaNonconformityException(NovaNonconformityFailure.validation))
                    put("risk_method", (intent.sourceMethod ?: NovaRiskMethod.fineKinney).wire)
                    if (intent.severity == null) put("risk_band", intent.riskBand
                        ?: throw NovaNonconformityException(NovaNonconformityFailure.severityUnknown))
                }
                NovaNonconformityIntent.Origin.expertItem -> {
                    put("item_id", intent.expertItemId ?: throw NovaNonconformityException(NovaNonconformityFailure.validation))
                    if (intent.severity == null) throw NovaNonconformityException(NovaNonconformityFailure.severityUnknown)
                    put("record_kind", intent.recordKind.name)
                    if (assignee.isNotEmpty()) put("assignee", assignee)
                    text(intent.hazardDescription)?.let { put("description", it) }
                }
                NovaNonconformityIntent.Origin.detailed -> {
                    if (intent.severity == null) throw NovaNonconformityException(NovaNonconformityFailure.severityUnknown)
                    put("record_kind", intent.recordKind.name)
                    if (assignee.isNotEmpty()) put("assignee", assignee)
                    mergeDetail(intent.hazardDescription, intent.controlMeasure, intent.legislation, intent.responsible, intent.score)
                    if (intent.evidenceAssetIds.isNotEmpty()) putJsonArray("evidence_asset_ids") { intent.evidenceAssetIds.forEach { add(it) } }
                }
            }
        }
        val function = if (intent.origin == NovaNonconformityIntent.Origin.finding) "isg_pilot_finding_file_v1" else "isg_nonconformity_mutate_v1"
        val envelope = call(function, mutation(scope, intent.origin.action, payload, operationId, mutationId))
            .decode(MutationEnvelope.serializer())
        check(scope)
        return OpenResult(envelope.row, envelope.outcome?.replayed ?: false)
    }

    /** Replaces the whole detail exactly as shown, so a cleared field really is cleared. */
    suspend fun setDetail(scope: NovaCompanyScope, id: String, draft: NovaNonconformityDetailDraft): NovaNonconformityRow {
        check(scope)
        if (!(draft.score.isEmpty || draft.score.isComplete)) throw NovaNonconformityException(NovaNonconformityFailure.validation)
        val payload = buildJsonObject {
            put("nonconformity_id", id)
            mergeDetail(draft.description, draft.measure, draft.legislation, draft.responsible, draft.score)
        }
        return mutate(scope, "set_detail", payload)
    }

    suspend fun detail(scope: NovaCompanyScope, id: String): NovaNonconformityRow {
        check(scope)
        val row = call("isg_nonconformity_read_v1", readArgs(scope.companyId, "detail", id = id)).decode(DetailEnvelope.serializer()).row
        check(scope); return row
    }

    suspend fun addAction(scope: NovaCompanyScope, id: String, description: String, assignee: String?, dueOn: String?) =
        mutate(scope, "add_action", buildJsonObject {
            put("nonconformity_id", id); put("description", description)
            text(assignee)?.let { put("assignee", it) }; dueOn?.let { put("due_on", it) }
        })

    suspend fun verify(scope: NovaCompanyScope, id: String, accepted: Boolean, note: String?) =
        mutate(scope, "verify", buildJsonObject {
            put("nonconformity_id", id); put("outcome", if (accepted) "accepted" else "rejected")
            text(note)?.let { put("note", it) }
        })

    /** The expected version travels with the move, so a record advanced meanwhile refuses. */
    suspend fun transition(scope: NovaCompanyScope, id: String, to: NovaNonconformityState, expectedVersion: Long,
                           reason: String, assignee: String = "") =
        mutate(scope, "transition", buildJsonObject {
            put("nonconformity_id", id); put("expected_version", expectedVersion); put("to_state", to.name)
            text(reason)?.let { put("reason", it) }; text(assignee)?.let { put("assignee", it) }
        })

    private suspend fun mutate(scope: NovaCompanyScope, action: String, payload: JsonObject): NovaNonconformityRow {
        check(scope)
        val row = call("isg_nonconformity_mutate_v1", mutation(scope, action, payload, UUID.randomUUID().toString(),
            UUID.randomUUID().toString())).decode(MutationEnvelope.serializer()).row
        check(scope); return row
    }

    /**
     * Every company the account can still read, one at a time. A failed company read fails
     * the whole board: an incomplete result must not become a convincing count.
     */
    suspend fun board(identity: IsgWorkspaceIdentity): List<NovaNonconformityEntry> {
        val companies = overview.overview(identity).filter { !it.isArchived }
        val result = mutableListOf<NovaNonconformityEntry>()
        for (company in companies) {
            val scope = NovaCompanyScope(identity, company.id)
            val rows = list(scope)
            val names = workplaces(scope).associate { it.id to it.name }
            result += rows.map { NovaNonconformityEntry(it, company.id, company.name, names[it.workplaceId]) }
        }
        val collator = java.text.Collator.getInstance(Locale.forLanguageTag("tr-TR"))
        return result.sortedWith { a, b ->
            if (a.row.openedOn == b.row.openedOn) collator.compare(a.row.title, b.row.title) else b.row.openedOn.compareTo(a.row.openedOn)
        }
    }

    suspend fun companyOptions(identity: IsgWorkspaceIdentity): List<NovaCompanyOption> =
        overview.overview(identity).filter { !it.isArchived }.map {
            NovaCompanyOption(it.id, it.name, "${it.workplaceCount} işyeri · ${it.personnelCount} personel", it.sector, it.hazardClass)
        }

    companion object {
        internal fun text(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

        /** Published Fine-Kinney values travel as text so no float rendering breaks the scale check. */
        internal fun scaleText(value: Double): String =
            if (value == Math.rint(value)) value.toLong().toString() else String.format(Locale.ROOT, "%.1f", value)

        /** The score itself is never sent; the server generates it from these inputs. */
        internal fun JsonObjectBuilder.mergeDetail(description: String?, measure: String?, legislation: String?,
                                                   responsible: String?, score: NovaRiskScoreInput) {
            text(description)?.let { put("description", it) }
            text(measure)?.let { put("control_measure", it) }
            text(legislation)?.let { put("legislation_ref", it) }
            text(responsible)?.let { put("responsible_contact", it) }
            val method = score.method ?: return
            if (!score.isComplete) return
            put("risk_method", method.wire)
            when (method) {
                NovaRiskMethod.fineKinney -> {
                    put("fk_probability", scaleText(score.probability ?: 0.0))
                    put("fk_frequency", scaleText(score.frequency ?: 0.0))
                    put("fk_severity", scaleText(score.severity ?: 0.0))
                }
                NovaRiskMethod.matrix5x5 -> {
                    put("m5_probability", score.matrixProbability ?: 0); put("m5_severity", score.matrixSeverity ?: 0)
                }
            }
        }
    }
}
