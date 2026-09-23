package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import javax.inject.Inject
import javax.inject.Singleton

/** Server aggregates only (iOS `NovaStatisticsSnapshot`): current stock and period activity; a missing source is never a zero. */
@Serializable data class NovaStatisticsSnapshot(
    @SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String,
    @SerialName("company_id") val companyId: String? = null, val months: Int, @SerialName("from_day") val fromDay: String, val today: String,
    val companies: List<Company>, @SerialName("company_count") val companyCount: Int, val personnel: Int, val workplaces: Int,
    val analyses: Int, val trainings: Int, @SerialName("trained_people") val trainedPeople: Int,
    @SerialName("training_enrollments") val trainingEnrollments: Int, val series: List<Month>, val findings: Findings? = null,
    val documents: Map<String, Int>? = null,
) {
    @Serializable data class Company(val id: String, val name: String, val personnel: Int, val workplaces: Int)
    @Serializable data class Month(val month: String, val analyses: Int, val trainings: Int) {
        val label: String get() {
            val names = listOf("Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara")
            val parts = month.split("-")
            val index = parts.getOrNull(1)?.toIntOrNull()
            return if (parts.size == 3 && index != null && index in 1..12) names[index - 1] else month
        }
    }
    @Serializable data class Findings(val open: Int, val overdue: Int, val pending: Int, val opened: Int, val closed: Int, val severity: Map<String, Int>)

    /** Every figure must answer for this owner, company and period, and add up, or the snapshot is refused. */
    fun valid(owner: String, company: String?, period: Int): Boolean {
        val counts = listOf(companyCount, personnel, workplaces, analyses, trainings, trainedPeople, trainingEnrollments)
        return schemaVersion == 1 && ownerId.sameId(owner) && (companyId?.lowercase() == company?.lowercase()) && months == period &&
            months in setOf(1, 3, 6, 12) && series.size == months && series.map { it.month }.toSet().size == months &&
            companies.map { it.id.lowercase() }.toSet().size == companies.size && (company == null || companies.any { it.id.sameId(company) }) &&
            counts.all { it >= 0 } && companies.all { it.personnel >= 0 && it.workplaces >= 0 } &&
            series.all { it.analyses >= 0 && it.trainings >= 0 } && series.sumOf { it.analyses } == analyses && series.sumOf { it.trainings } == trainings &&
            (findings?.let { f -> listOf(f.open, f.overdue, f.pending, f.opened, f.closed).all { it >= 0 } && f.overdue <= f.open && f.pending <= f.open &&
                f.severity.values.all { it >= 0 } } ?: true) && (documents?.values?.all { it >= 0 } ?: true)
    }

    val selectedCompanies get() = companies.filter { companyId == null || it.id.sameId(companyId) }
    val documentTotal get() = documents?.values?.sum()

    companion object {
        fun dayLabel(value: String): String {
            val parts = value.split("-")
            return if (parts.size == 3) "${parts[2]}.${parts[1]}.${parts[0]}" else value
        }
    }
}

/** A read-time projection of every tracked module per company (iOS `NovaModuleTrackingSnapshot`). No legal score. */
@Serializable data class NovaModuleTrackingSnapshot(val today: String, val rows: List<Row>) {
    @Serializable data class Row(
        @SerialName("company_id") val companyId: String, @SerialName("company_name") val companyName: String, val kind: String,
        val available: Boolean, val total: Int? = null, val pending: Int? = null, val overdue: Int? = null, val upcoming: Int? = null,
        val review: Int? = null, @SerialName("next_on") val nextOn: String? = null,
    )
    data class Summary(val id: String, val available: Boolean, val total: Int, val pending: Int, val overdue: Int, val upcoming: Int,
                       val review: Int, val nextOn: String?) {
        val title: String get() = when (id) {
            "emergency_plan" -> "Acil Durum Planları"; "drill" -> "Tatbikatlar"; "appointment" -> "Atamalar"
            "ppe" -> "KKD Zimmetleri"; "checklist_run" -> "Kontrol Listeleri"; else -> NovaProcessKind.get(id).title
        }
        val symbol: String get() = when (id) {
            "emergency_plan" -> "light.beacon.max"; "drill" -> "figure.run"; "appointment" -> "person.badge.shield.checkmark"
            "ppe" -> "shield"; "checklist_run" -> "checklist"; "annual_work_plan", "annual_work_item" -> "calendar"
            "board", "board_decision" -> "person.3"; "site_visit" -> "mappin.and.ellipse"; "contractor" -> "building.2"; else -> "doc.text"
        }
        /** The module page a row opens: child records open their parent's list. */
        val route: String get() = when (id) { "annual_work_item" -> "annual_work_plan"; "board_decision" -> "board"; else -> id }
    }

    /** Overdue first, then pending, then by title. */
    val summaries: List<Summary> get() = rows.groupBy { it.kind }.map { (kind, values) ->
        Summary(kind, values.all { it.available }, values.sumOf { it.total ?: 0 }, values.sumOf { it.pending ?: 0 }, values.sumOf { it.overdue ?: 0 },
            values.sumOf { it.upcoming ?: 0 }, values.sumOf { it.review ?: 0 }, values.mapNotNull { it.nextOn }.minOrNull())
    }.sortedWith(compareByDescending<Summary> { it.overdue }.thenByDescending { it.pending }
        .thenBy(java.text.Collator.getInstance(java.util.Locale.forLanguageTag("tr-TR"))) { it.title })
}

class NovaStatisticsException : Exception("STATISTICS_UNAVAILABLE")

@Singleton
class NovaStatisticsService @Inject constructor(private val transport: NovaExpertTransport) {
    private suspend fun <T> call(identity: IsgWorkspaceIdentity, function: String, params: JsonObject, serializer: KSerializer<T>): T {
        if (transport.identityNow() != identity) throw NovaStatisticsException()
        val data = try { transport.execute(function, params, maxBytes = 2_097_152) } catch (_: NovaExpertFailure) {
            currentCoroutineContext().ensureActive(); throw NovaStatisticsException()
        }
        if (transport.identityNow() != identity) throw NovaStatisticsException()
        return runCatching { novaJson.decodeFromJsonElement(serializer, data) }.getOrNull() ?: throw NovaStatisticsException()
    }

    suspend fun load(identity: IsgWorkspaceIdentity, company: String?, months: Int): NovaStatisticsSnapshot {
        val result = call(identity, "isg_statistics_v1", buildJsonObject {
            put("p_company", company?.let(::JsonPrimitive) ?: JsonNull); put("p_months", months)
        }, NovaStatisticsSnapshot.serializer())
        if (!result.valid(identity.userId, company, months)) throw NovaStatisticsException()
        return result
    }

    suspend fun tracking(identity: IsgWorkspaceIdentity, company: String?): NovaModuleTrackingSnapshot =
        call(identity, "isg_pilot_module_tracking_v2", buildJsonObject { put("p_company", company?.let(::JsonPrimitive) ?: JsonNull) },
            NovaModuleTrackingSnapshot.serializer())
}
