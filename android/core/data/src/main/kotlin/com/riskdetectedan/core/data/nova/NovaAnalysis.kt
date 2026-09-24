package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.AnalysisItemReaction
import com.riskdetectedan.core.data.analysis.AnalysisResultAccess
import com.riskdetectedan.core.data.analysis.AnalysisResultHubItem
import com.riskdetectedan.core.data.analysis.AnalysisResultHubRepository
import com.riskdetectedan.core.data.analysis.AnalysisResultHubResponse
import com.riskdetectedan.core.data.analysis.AnalysisResultSectionId
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisStatus
import com.riskdetectedan.core.data.analysis.CreateAnalysisRequest
import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingMeasure
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.FindingsRepository
import com.riskdetectedan.core.data.analysis.PhotoRepository
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.IsgWorkspaceRepository
import com.riskdetectedan.core.data.isg.NovaExpertTicket
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import com.riskdetectedan.core.data.profile.ProfileRepository
import com.riskdetectedan.core.data.reports.PdfReportFileName
import com.riskdetectedan.core.data.reports.PdfReportGenerator
import com.riskdetectedan.core.data.reports.PdfReportInput
import com.riskdetectedan.core.data.reports.ReportsRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Keeps analysis titles and stamps quiet (iOS `NovaAnalysisPresentation`). */
object NovaAnalysisPresentation {
    private const val months = "Oca(?:k)?|Şub(?:at)?|Mar(?:t)?|Nis(?:an)?|May(?:ıs)?|Haz(?:iran)?|Tem(?:muz)?|Ağu(?:stos)?|Eyl(?:ül)?|Eki(?:m)?|Kas(?:ım)?|Ara(?:lık)?"
    private val trailingStamp = Regex("""\s*[·-]?\s*\d{1,2}\s+(?:$months)\s+\d{4}(?:\s*[·-]?\s*\d{1,2}:\d{2})?\s*$""", RegexOption.IGNORE_CASE)
    private val trailingNumeric = Regex("""\s*[·-]?\s*\d{1,2}[./-]\d{1,2}[./-]\d{4}(?:\s*[·-]?\s*\d{1,2}:\d{2})?\s*$""")
    private val time = Regex("""\s*[·-]?\s*\d{1,2}:\d{2}\s*$""")

    fun title(value: String): String = value.replace(trailingStamp, "").replace(trailingNumeric, "").trim().ifEmpty { value }
    fun dateOnly(value: String): String = value.replace(time, "").trim()
}

/** The four parts of a finished analysis, in product order. */
enum class NovaAnalysisSectionKind(val wire: String) {
    riskAnalysis("risk_analysis"), expertRecommendations("expert_recommendations"),
    trainingRecommendations("training_recommendations"), approvedNotebook("approved_notebook");
    /** Only the risk analysis arrives scored; nothing else may be filed with a mapped band. */
    val isScored: Boolean get() = this == riskAnalysis
    val isFileable: Boolean get() = this != approvedNotebook
}

data class NovaAnalysisScoreFactor(val label: String, val value: Double)

/** What one published method says about one item; both number and band are the server's. */
data class NovaAnalysisScore(val band: String?, val value: Double?, val factors: List<NovaAnalysisScoreFactor> = emptyList()) {
    val isUnreadableBand: Boolean get() = band != null && band !in setOf("low", "medium", "high", "critical")
}

data class NovaAnalysisMeasure(val id: String, val title: String, val text: String, val isPreventive: Boolean)

enum class NovaAnalysisReaction { none, like, dislike }

data class NovaAnalysisItem(
    val id: String, val ordinal: Int, val title: String, val category: String?, val body: String, val measure: String?,
    val references: String?, val rootCause: String? = null, val measures: List<NovaAnalysisMeasure> = emptyList(),
    val audience: String? = null, val durationLabel: String? = null, val durationValue: String? = null, val durationNote: String? = null,
    val photoIndices: List<Int> = emptyList(), val reaction: NovaAnalysisReaction = NovaAnalysisReaction.none,
    val fineKinney: NovaAnalysisScore? = null, val matrix: NovaAnalysisScore? = null,
) {
    fun score(method: NovaRiskMethod) = if (method == NovaRiskMethod.fineKinney) fineKinney else matrix
    fun band(method: NovaRiskMethod) = score(method)?.band
    fun value(method: NovaRiskMethod) = score(method)?.value
    fun isUnreadableBand(method: NovaRiskMethod) = score(method)?.isUnreadableBand ?: false
    val hasRootCause: Boolean get() = !rootCause.isNullOrBlank()
    val hasReferences: Boolean get() = !references.isNullOrBlank()
    val hasPreventive: Boolean get() = measures.any { it.isPreventive }
}

data class NovaAnalysisSection(val kind: NovaAnalysisSectionKind, val items: List<NovaAnalysisItem>, val isTeaser: Boolean) {
    fun distribution(method: NovaRiskMethod) = listOf("critical", "high", "medium", "low").map { band -> band to items.count { it.band(method) == band } }
    fun highest(method: NovaRiskMethod) = items.maxByOrNull { it.value(method) ?: -1.0 }
}

data class NovaAnalysisDetailData(
    val analysisId: String, val title: String, val createdOn: String, val methodLabel: String, val method: NovaRiskMethod,
    val companyId: String?, val companyName: String?, val sections: List<NovaAnalysisSection>, val isProjectionMissing: Boolean,
    val photoCount: Int = 0, val sectorLabel: String? = null, val focusLabels: List<String> = emptyList(),
) {
    fun section(kind: NovaAnalysisSectionKind) = sections.firstOrNull { it.kind == kind }
}

data class NovaAnalysisSummary(
    val id: String, val title: String, val createdOn: String, val companyName: String?, val findingCount: Int?, val photoCount: Int = 0,
    val sectorLabel: String? = null, val highestBand: String? = null, val focusLabel: String? = null, val isReviewed: Boolean = false,
    val createdAt: Instant? = null,
) {
    val isUnassigned: Boolean get() = companyName == null
    fun matches(query: String): Boolean {
        val needle = query.trim().lowercase(Locale.forLanguageTag("tr-TR"))
        return needle.isEmpty() || listOf(title, companyName.orEmpty(), sectorLabel.orEmpty(), focusLabel.orEmpty(), createdOn)
            .any { it.lowercase(Locale.forLanguageTag("tr-TR")).contains(needle) }
    }
}

data class NovaAnalysisListStats(val total: Int, val critical: Int, val findings: Int)

data class NovaAnalysisReportEntry(
    val id: String, val title: String, val fileName: String, val createdOn: String, val companyName: String?, val format: String,
    val methodLabel: String, val kindLabel: String, val fileSize: Long?, val analysisId: String?, val createdAt: Instant? = null,
    val storagePath: String? = null, val mimeType: String? = null, val assetId: String? = null, val downloadBucket: String? = null,
    val downloadPath: String? = null,
) {
    val isSpreadsheet: Boolean get() = format.lowercase().contains("xls") || format.lowercase() == "excel"
    fun matches(query: String): Boolean {
        val needle = query.trim().lowercase(Locale.forLanguageTag("tr-TR"))
        return needle.isEmpty() || listOf(title, fileName, companyName.orEmpty(), kindLabel, createdOn)
            .any { it.lowercase(Locale.forLanguageTag("tr-TR")).contains(needle) }
    }
}

data class NovaAnalysisCompanyOption(val id: String, val name: String, val detail: String, val sector: String?)

data class NovaAnalysisFindingEdit(val analysisId: String, val findingId: String, val title: String? = null, val category: String? = null,
                                   val body: String? = null, val measure: String? = null, val references: String? = null,
                                   val score: NovaRiskScoreInput = NovaRiskScoreInput())

data class NovaAnalysisFileRequest(val companyId: String?, val item: NovaAnalysisItem, val section: NovaAnalysisSectionKind, val workplaceId: String?,
                                   val recordKind: NovaNonconformityRecordKind, val band: String?, val severity: NovaNonconformitySeverity?,
                                   val sourceMethod: NovaRiskMethod? = null)

enum class NovaAnalysisReportFormat { pdf, excel }

data class NovaAnalysisReportRequest(val analysisId: String, val format: NovaAnalysisReportFormat, val method: NovaRiskMethod, val companyId: String?)

/** The outcome of filing an analysis item as a record (iOS `NovaFindingOutcome`). */
sealed interface NovaFindingOutcome {
    data object Opened : NovaFindingOutcome
    data object AlreadyOpen : NovaFindingOutcome
    data class Failed(val message: String) : NovaFindingOutcome
    /** The nonconformity boundary refused; the screen words it. */
    data class Refused(val failure: NovaNonconformityFailure) : NovaFindingOutcome
}

class NovaAnalysisException(message: String) : Exception(message)

/**
 * Composition between the NOVA analysis screens and the pipeline the product already ships (iOS
 * `NovaAnalysisWorkspace` + `NovaExpertAnalysisBackend`). A personal account reads its own analyses; an
 * organization ticket reads the workspace's through `isg_expert_analysis_v1` and never falls back.
 */
@Singleton
class NovaAnalysisService @Inject constructor(
    private val client: SupabaseClient,
    private val transport: NovaExpertTransport,
    private val workspace: IsgWorkspaceRepository,
    private val overview: NovaOverviewService,
    private val findings: FindingsRepository,
    private val photos: PhotoRepository,
    private val hub: AnalysisResultHubRepository,
    private val reports: ReportsRepository,
    private val pdf: PdfReportGenerator,
    private val profiles: ProfileRepository,
    private val nonconformity: NovaNonconformityService,
    private val files: NovaFileLibraryService,
    private val analyses: com.riskdetectedan.core.data.analysis.AnalysisRepository,
) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    @Serializable private data class AnalysisRow(
        val id: String, val title: String, val canvas: String = "", val status: String = "",
        @SerialName("company_id") val companyId: String? = null, @SerialName("finding_count") val findingCount: Int = 0,
        @SerialName("photo_count") val photoCount: Int? = null, @SerialName("analysis_sector") val analysisSector: String? = null,
        @SerialName("highest_band_fk") val highestBandFk: String? = null, @SerialName("highest_band_m5") val highestBandM5: String? = null,
        @SerialName("created_at") val createdAt: String? = null, @SerialName("ai_summary") val aiSummary: String? = null,
    )

    @Serializable private data class ReportRow(
        val id: String, @SerialName("analysis_id") val analysisId: String? = null, @SerialName("company_id") val companyId: String? = null,
        @SerialName("company_snapshot") val companySnapshot: JsonElement? = null, val format: String? = null, val kind: String = "",
        val method: String = "", val title: String = "", @SerialName("storage_path") val storagePath: String? = null,
        @SerialName("file_name") val fileName: String = "", @SerialName("mime_type") val mimeType: String? = null,
        @SerialName("file_size") val fileSize: Long? = null, @SerialName("created_at") val createdAt: String? = null,
    )

    private fun organization(): NovaExpertTicket? = transport.capture()?.takeIf { it.access.workspaceId != null }

    private suspend fun call(action: String, payload: JsonObject = JsonObject(emptyMap()), ticket: NovaExpertTicket): JsonObject =
        transport.executeObject("isg_expert_analysis_v1", buildJsonObject { put("p_action", action); put("p_payload", payload) }, ticket)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaAnalysisException("denied")
    }

    private suspend fun companyNames(identity: IsgWorkspaceIdentity) =
        runCatching { overview.overview(identity) }.getOrDefault(emptyList()).associate { it.id.lowercase() to it.name }

    /** The expert's own method opens the analysis screens; Fine-Kinney when none was chosen. */
    suspend fun preferredMethod(identity: IsgWorkspaceIdentity): NovaRiskMethod =
        (profiles.fetchProfile(identity.userId) as? RdResult.Success)?.value?.preferredMethod?.let(NovaRiskMethod::of) ?: NovaRiskMethod.fineKinney

    // MARK: list

    /** One page of completed analyses, newest first; `hasMore` is a full page, never a guess. */
    suspend fun summaries(identity: IsgWorkspaceIdentity, method: NovaRiskMethod, limit: Int = 10, offset: Int = 0): Pair<List<NovaAnalysisSummary>, Boolean> {
        organization()?.let { ticket ->
            val page = call("list", buildJsonObject { put("limit", limit); put("offset", offset) }, ticket)
            val rows = page["rows"]?.jsonArray.orEmpty().map { it.jsonObject }.map { row ->
                fun text(key: String) = row[key]?.jsonPrimitive?.contentOrNull
                NovaAnalysisSummary(text("id")!!, text("title").orEmpty(), day(text("created_at")), text("company_name"),
                    row["finding_count"]?.jsonPrimitive?.intOrNull, highestBand = if (method == NovaRiskMethod.fineKinney) text("highest_band_fk")
                    else text("highest_band_m5"), isReviewed = true, createdAt = instant(text("created_at")))
            }
            return rows to (page["has_more"]?.jsonPrimitive?.booleanOrNull == true)
        }
        check(identity)
        val rows = client.postgrest.from("analyses").select {
            filter { eq("status", "completed"); eq("kind", "photo") }
            order("created_at", Order.DESCENDING)
            range(offset.toLong(), (offset + limit - 1).toLong())
        }.decodeList<AnalysisRow>()
        val names = companyNames(identity)
        return rows.map { row ->
            NovaAnalysisSummary(row.id, row.title, day(row.createdAt),
                row.companyId?.let { names[it.lowercase()] ?: "Bağlı firma" }, row.findingCount, row.photoCount ?: 0,
                row.analysisSector?.let(AnalysisSector::fromId)?.titleTr,
                if (method == NovaRiskMethod.fineKinney) row.highestBandFk else row.highestBandM5, focusLabel(row.canvas),
                row.status == "completed", instant(row.createdAt))
        } to (rows.size == limit)
    }

    /** Lifetime counts come from the server aggregate, never from the loaded rows. */
    suspend fun stats(identity: IsgWorkspaceIdentity, method: NovaRiskMethod?, companyId: String? = null): NovaAnalysisListStats {
        val ticket = transport.capture()
        check(identity)
        val response = transport.executeObject("isg_analysis_list_stats_v1", buildJsonObject {
            put("p_method", method?.code?.let(::JsonPrimitive) ?: JsonNull); put("p_company", companyId?.let(::JsonPrimitive) ?: JsonNull)
        }, ticket)
        fun int(key: String) = response[key]?.jsonPrimitive?.intOrNull ?: -1
        val total = int("total"); val critical = int("critical"); val findingCount = int("findings")
        if (int("schema_version") != 1 || response["owner_id"]?.jsonPrimitive?.contentOrNull?.equals(identity.userId, true) != true ||
            response["workspace_id"]?.jsonPrimitive?.contentOrNull != ticket?.access?.workspaceId ||
            response["company_id"]?.jsonPrimitive?.contentOrNull != companyId || response["method"]?.jsonPrimitive?.contentOrNull != method?.code ||
            total < 0 || critical !in 0..total || findingCount < 0) throw NovaAnalysisException("denied")
        transport.validate(ticket)
        return NovaAnalysisListStats(total, critical, findingCount)
    }

    /** The first picture of an analysis; a missing picture is simply absent. */
    suspend fun thumbnail(analysisId: String, context: IsgWorkspaceContext?): ByteArray? = try {
        if (organization() != null) photos(analysisId, context).firstOrNull()
        else {
            val path = (photos.firstPhotoPaths(listOf(analysisId)) as? RdResult.Success)?.value?.get(analysisId)
            path?.let { (photos.downloadPhoto(it) as? RdResult.Success)?.value }
        }
    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { null }

    /** Every picture of one analysis, in order; one that cannot be read is left out. */
    suspend fun photos(analysisId: String, context: IsgWorkspaceContext?): List<ByteArray> {
        organization()?.let { ticket ->
            val scope = context ?: return emptyList()
            return call("detail", buildJsonObject { put("analysis_id", analysisId) }, ticket)["photos"]?.jsonArray.orEmpty().mapNotNull { photo ->
                val asset = photo.jsonObject["asset_id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                runCatching { workspace.downloadAsset(scope, asset) }.getOrNull().also { transport.validate(ticket) }
            }
        }
        val rows = (photos.listPhotos(analysisId) as? RdResult.Success)?.value.orEmpty()
        return rows.mapNotNull { (photos.downloadPhoto(it.storagePath) as? RdResult.Success)?.value }
    }

    // MARK: reports

    suspend fun reports(identity: IsgWorkspaceIdentity, limit: Int = 10, offset: Int = 0): Pair<List<NovaAnalysisReportEntry>, Boolean> {
        organization()?.let { ticket ->
            val page = call("reports", buildJsonObject { put("limit", limit); put("offset", offset) }, ticket)
            fun map(rows: List<JsonObject>) = rows.map { row ->
                fun text(key: String) = row[key]?.jsonPrimitive?.contentOrNull
                NovaAnalysisReportEntry(text("id")!!, text("title").orEmpty(), text("file_name").orEmpty(), day(text("created_at")),
                    text("company_name"), text("format") ?: "pdf", "", "İSG Analizi", row["file_size"]?.jsonPrimitive?.longOrNull,
                    text("analysis_id"), instant(text("created_at")), assetId = text("asset_id"), downloadBucket = text("download_bucket"),
                    downloadPath = text("download_path"))
            }
            val hasMore = page["has_more"]?.jsonPrimitive?.booleanOrNull
            val rows = page["rows"]?.jsonArray.orEmpty().map { it.jsonObject }
            // Older pilot deployments ignored offset: read one expanded page so the list never repeats.
            if (hasMore == null && offset > 0) {
                val expanded = call("reports", buildJsonObject { put("limit", minOf(offset + limit, 100)); put("offset", 0) }, ticket)["rows"]
                    ?.jsonArray.orEmpty().map { it.jsonObject }
                return map(expanded.drop(offset).take(limit)) to (expanded.size > offset + limit)
            }
            return map(rows) to (hasMore ?: (rows.size == limit))
        }
        check(identity)
        val rows = client.postgrest.from("reports").select(Columns.raw("id,analysis_id,company_id,company_snapshot,format,kind,method,title," +
            "storage_path,file_name,mime_type,file_size,created_at,analyses!inner(kind)")) {
            filter { eq("analyses.kind", "photo") }
            order("created_at", Order.DESCENDING)
            range(offset.toLong(), (offset + limit - 1).toLong())
        }.decodeList<ReportRow>()
        val names = companyNames(identity)
        return rows.map { row ->
            NovaAnalysisReportEntry(row.id, row.title, row.fileName, day(row.createdAt),
                row.companyId?.let { names[it.lowercase()] } ?: (row.companySnapshot as? JsonObject)?.get("name")?.jsonPrimitive?.contentOrNull,
                row.format ?: "pdf", NovaRiskMethod.of(row.method)?.label ?: row.method, row.kind, row.fileSize, row.analysisId,
                instant(row.createdAt), row.storagePath, row.mimeType)
        } to (rows.size == limit)
    }

    suspend fun downloadReport(entry: NovaAnalysisReportEntry, identity: IsgWorkspaceIdentity, context: IsgWorkspaceContext?): ByteArray {
        check(identity)
        val asset = entry.assetId
        return when {
            organization() != null && asset != null && context != null -> workspace.downloadAsset(context, asset)
            entry.downloadBucket != null && entry.downloadPath != null -> files.download(identity, entry.downloadBucket, entry.downloadPath)
            entry.storagePath != null -> client.storage.from("reports").downloadAuthenticated(entry.storagePath)
            else -> throw NovaAnalysisException("unavailable")
        }
    }

    // MARK: companies

    suspend fun companyOptions(identity: IsgWorkspaceIdentity): List<NovaAnalysisCompanyOption> =
        overview.overview(identity).filter { !it.isArchived }.map {
            NovaAnalysisCompanyOption(it.id, it.name, "${it.workplaceCount} işyeri · ${it.personnelCount} personel", it.sector)
        }

    // MARK: detail

    suspend fun detail(analysisId: String, identity: IsgWorkspaceIdentity, method: NovaRiskMethod): NovaAnalysisDetailData {
        organization()?.let { ticket -> return organizationDetail(analysisId, method, ticket) }
        check(identity)
        val row = client.postgrest.from("analyses").select { filter { eq("id", analysisId) }; limit(1) }.decodeList<AnalysisRow>().firstOrNull()
            ?: throw NovaAnalysisException("unavailable")
        val saved = (findings.fetchFindings(analysisId) as? RdResult.Success)?.value ?: throw NovaAnalysisException("unavailable")
        val fresh = instant(row.createdAt)?.let { kotlin.math.abs(Instant.now().epochSecond - it.epochSecond) < 120 } == true
        // A fresh result may still be projecting; a historical one will not gain a missing projection by polling.
        var loaded = (hub.load(analysisId) as? RdResult.Success)?.value
        if (fresh) repeat(10) {
            if (loaded?.enabled == true && loaded!!.sections.isNotEmpty()) return@repeat
            delay(1_500)
            loaded = (hub.load(analysisId) as? RdResult.Success)?.value
        }
        val photoCount = (photos.listPhotos(analysisId) as? RdResult.Success)?.value?.size ?: 0
        val name = row.companyId?.let { companyNames(identity)[it.lowercase()] }
        return detailData(row.id, row.title, row.createdAt, row.companyId, name, row.canvas, row.analysisSector, photoCount, saved,
            loaded?.takeIf { it.enabled }, method)
    }

    private suspend fun organizationDetail(analysisId: String, method: NovaRiskMethod, ticket: NovaExpertTicket): NovaAnalysisDetailData {
        val value = call("detail", buildJsonObject { put("analysis_id", analysisId) }, ticket)
        val header = value["analysis"]!!.jsonObject
        val feedback = value["feedback"]?.jsonObject.orEmpty().mapValues { it.value.jsonPrimitive.content }
        fun items(key: String): List<NovaAnalysisItem> = value[key]?.jsonArray.orEmpty().mapIndexed { index, element ->
            val row = element.jsonObject
            fun text(name: String) = row[name]?.jsonPrimitive?.contentOrNull
            fun double(name: String) = row[name]?.jsonPrimitive?.doubleOrNull
            fun int(name: String) = row[name]?.jsonPrimitive?.intOrNull
            val scored = row["is_scored"]?.jsonPrimitive?.booleanOrNull == true
            NovaAnalysisItem(text("id")!!, int("ordinal") ?: int("display_order") ?: (index + 1), text("title").orEmpty(), text("category"),
                text("body") ?: text("description").orEmpty(), text("recommendation") ?: text("recommended_action"), text("references_text"),
                audience = text("audience"), durationValue = int("duration_minutes")?.let { "$it dk" },
                photoIndices = row["source_photo_indices"]?.jsonArray?.mapNotNull { it.jsonPrimitive.intOrNull }.orEmpty(),
                reaction = feedback[text("id")!!.lowercase()]?.let { runCatching { NovaAnalysisReaction.valueOf(it) }.getOrNull() } ?: NovaAnalysisReaction.none,
                fineKinney = if (scored) NovaAnalysisScore(text("fk_band"), double("fk_score"), listOfNotNull(double("fk_probability")?.let { NovaAnalysisScoreFactor("O", it) },
                    double("fk_frequency")?.let { NovaAnalysisScoreFactor("F", it) }, double("fk_severity")?.let { NovaAnalysisScoreFactor("Ş", it) })) else null,
                matrix = if (scored) NovaAnalysisScore(text("m5_band"), int("m5_score")?.toDouble(), listOfNotNull(int("m5_probability")?.let {
                    NovaAnalysisScoreFactor("O", it.toDouble()) }, int("m5_severity")?.let { NovaAnalysisScoreFactor("Ş", it.toDouble()) })) else null)
        }
        return NovaAnalysisDetailData(analysisId, header["title"]!!.jsonPrimitive.content, day(header["created_at"]?.jsonPrimitive?.contentOrNull),
            method.label, method, value["company_id"]?.jsonPrimitive?.contentOrNull, value["company_name"]?.jsonPrimitive?.contentOrNull, listOf(
                NovaAnalysisSection(NovaAnalysisSectionKind.riskAnalysis, items("risk_findings"), false),
                NovaAnalysisSection(NovaAnalysisSectionKind.expertRecommendations, items("expert_items"), false),
                NovaAnalysisSection(NovaAnalysisSectionKind.trainingRecommendations, items("training_items"), false),
                NovaAnalysisSection(NovaAnalysisSectionKind.approvedNotebook, emptyList(), false),
            ), false, value["photos"]?.jsonArray?.size ?: 0)
    }

    /** Pure assembly: the hub's full projection when present, else the durable finding rows split by scoring. */
    private fun detailData(id: String, title: String, createdAt: String?, companyId: String?, companyName: String?, canvas: String,
                           sector: String?, photoCount: Int, saved: List<Finding>, loaded: AnalysisResultHubResponse?,
                           method: NovaRiskMethod): NovaAnalysisDetailData {
        val complete = loaded != null && NovaAnalysisSectionKind.entries.all { kind -> loaded.sections.any { it.id.wire() == kind.wire } }
        val ordered = saved.sortedBy { it.ordinal }
        val sections = NovaAnalysisSectionKind.entries.map { kind ->
            loaded?.sections?.firstOrNull { it.id.wire() == kind.wire }?.let { section ->
                NovaAnalysisSection(kind, section.items.mapIndexed { index, item -> hubItem(item, index, kind) }, section.access == AnalysisResultAccess.Teaser)
            } ?: NovaAnalysisSection(kind, when (kind) {
                NovaAnalysisSectionKind.riskAnalysis -> ordered.filter(::isScored)
                NovaAnalysisSectionKind.expertRecommendations -> ordered.filterNot(::isScored)
                else -> emptyList()
            }.map { fallbackItem(it, kind) }, false)
        }
        val focuses = canvas.split(",").mapNotNull { raw -> AnalysisCanvas.all.firstOrNull { it.id == raw.trim() }?.title }
        return NovaAnalysisDetailData(id, title, day(createdAt), method.label, method, companyId, companyName, sections, !complete, photoCount,
            sector?.let(AnalysisSector::fromId)?.titleTr, focuses)
    }

    private fun AnalysisResultSectionId.wire(): String = when (this) {
        AnalysisResultSectionId.RiskAnalysis -> "risk_analysis"; AnalysisResultSectionId.ExpertRecommendations -> "expert_recommendations"
        AnalysisResultSectionId.TrainingRecommendations -> "training_recommendations"; AnalysisResultSectionId.ApprovedNotebook -> "approved_notebook"
    }

    /** Mirrors the server's `findingSection` rule: `is_scored` wins, the item class classifies older rows. */
    private fun isScored(finding: Finding): Boolean = finding.isScored &&
        finding.itemClass.lowercase() !in setOf("assurance_requirement", "verification_request", "positive_control", "not_assessable")

    private fun measures(values: List<FindingMeasure>?) = values.orEmpty().mapIndexed { index, measure ->
        NovaAnalysisMeasure("$index", measure.title.ifBlank { if (measure.kind == "preventive") "Önleyici" else "Düzeltici" }, measure.text,
            measure.kind == "preventive")
    }

    private fun fineKinney(band: String?, score: Double?, probability: Double?, frequency: Double?, severity: Double?): NovaAnalysisScore? {
        if (band == null && score == null) return null
        val factors = if (probability != null && frequency != null && severity != null)
            listOf(NovaAnalysisScoreFactor("O", probability), NovaAnalysisScoreFactor("F", frequency), NovaAnalysisScoreFactor("Ş", severity)) else emptyList()
        return NovaAnalysisScore(band, score, factors)
    }

    private fun matrix(band: String?, score: Int?, probability: Int?, severity: Int?): NovaAnalysisScore? {
        if (band == null && score == null) return null
        val factors = if (probability != null && severity != null)
            listOf(NovaAnalysisScoreFactor("O", probability.toDouble()), NovaAnalysisScoreFactor("Ş", severity.toDouble())) else emptyList()
        return NovaAnalysisScore(band, score?.toDouble(), factors)
    }

    private fun fallbackItem(finding: Finding, kind: NovaAnalysisSectionKind) = NovaAnalysisItem(finding.id, finding.ordinal, finding.title,
        finding.category, finding.description.orEmpty(), finding.recommendedAction, finding.referencesText, finding.rootCauseText,
        measures(finding.recommendedMeasures), photoIndices = finding.sourcePhotoIndices,
        fineKinney = if (kind.isScored) fineKinney(finding.fkBand, finding.fkScore, finding.fkProbability, finding.fkFrequency, finding.fkSeverity) else null,
        matrix = if (kind.isScored) matrix(finding.m5Band, finding.m5Score, finding.m5Probability, finding.m5Severity) else null)

    private fun hubItem(value: AnalysisResultHubItem, index: Int, kind: NovaAnalysisSectionKind) = NovaAnalysisItem(value.id,
        value.ordinal ?: value.displayOrder ?: (index + 1), value.displayTitle, value.categoryLabel ?: value.category,
        value.displayBody.ifEmpty { value.text.orEmpty() }, value.recommendedAction ?: value.recommendationText,
        value.referencesText ?: value.referenceText, value.rootCauseText, measures(value.recommendedMeasures), value.audienceLabel,
        value.durationLabel, value.durationValue, value.durationNote, value.sourcePhotoIndices, when (value.userReaction) {
            AnalysisItemReaction.Like -> NovaAnalysisReaction.like; AnalysisItemReaction.Dislike -> NovaAnalysisReaction.dislike
            else -> NovaAnalysisReaction.none },
        if (kind.isScored) fineKinney(value.fkBand, value.fkScore, value.fkProbability, value.fkFrequency, value.fkSeverity) else null,
        if (kind.isScored) matrix(value.m5Band, value.m5Score, value.m5Probability, value.m5Severity) else null)

    // MARK: mutations

    suspend fun assign(analysisId: String, companyId: String, identity: IsgWorkspaceIdentity) {
        organization()?.let { ticket ->
            call("assign", buildJsonObject { put("analysis_id", analysisId); put("company_id", companyId) }, ticket); return
        }
        check(identity)
        client.postgrest.from("analyses").update(buildJsonObject { put("company_id", companyId) }) { filter { eq("id", analysisId) } }
    }

    private suspend fun version(analysisId: String, findingId: String): Int =
        (findings.fetchFindings(analysisId) as? RdResult.Success)?.value?.firstOrNull { it.id.equals(findingId, true) }?.findingVersion
            ?: throw NovaAnalysisException("unavailable")

    suspend fun edit(change: NovaAnalysisFindingEdit, identity: IsgWorkspaceIdentity) {
        fun clean(value: String?) = value?.trim()?.takeIf { it.isNotEmpty() }
        organization()?.let { ticket ->
            call("edit", buildJsonObject {
                put("analysis_id", change.analysisId); put("item_id", change.findingId)
                listOf("title" to change.title, "category" to change.category, "body" to change.body, "measure" to change.measure,
                    "references" to change.references).forEach { (key, value) -> value?.let { put(key, it) } }
                if (change.score.isComplete) when (change.score.method) {
                    NovaRiskMethod.fineKinney -> {
                        change.score.probability?.let { put("fk_probability", it.toString()) }
                        change.score.frequency?.let { put("fk_frequency", it.toString()) }
                        change.score.severity?.let { put("fk_severity", it.toString()) }
                    }
                    NovaRiskMethod.matrix5x5 -> {
                        change.score.matrixProbability?.let { put("m5_probability", it) }; change.score.matrixSeverity?.let { put("m5_severity", it) }
                    }
                    null -> Unit
                }
            }, ticket)
            return
        }
        check(identity)
        val score = change.score.takeIf { it.isComplete }
        val patch = FindingPatch(title = clean(change.title), category = clean(change.category), description = clean(change.body),
            recommendedAction = clean(change.measure), referencesText = clean(change.references),
            fkProbability = score?.probability.takeIf { score?.method == NovaRiskMethod.fineKinney },
            fkFrequency = score?.frequency.takeIf { score?.method == NovaRiskMethod.fineKinney },
            fkSeverity = score?.severity.takeIf { score?.method == NovaRiskMethod.fineKinney },
            m5Probability = score?.matrixProbability.takeIf { score?.method == NovaRiskMethod.matrix5x5 },
            m5Severity = score?.matrixSeverity.takeIf { score?.method == NovaRiskMethod.matrix5x5 })
        val result = findings.updateFinding(change.analysisId, change.findingId, version(change.analysisId, change.findingId), patch)
        if (result is RdResult.Failure) throw NovaAnalysisException(result.message)
    }

    suspend fun remove(analysisId: String, findingId: String, identity: IsgWorkspaceIdentity) {
        organization()?.let { ticket ->
            call("remove", buildJsonObject { put("analysis_id", analysisId); put("item_id", findingId) }, ticket); return
        }
        check(identity)
        val result = findings.deleteFinding(analysisId, findingId, version(analysisId, findingId))
        if (result is RdResult.Failure) throw NovaAnalysisException(result.message)
    }

    suspend fun react(analysisId: String, item: NovaAnalysisItem, section: NovaAnalysisSectionKind, reaction: NovaAnalysisReaction,
                      identity: IsgWorkspaceIdentity) {
        organization()?.let { ticket ->
            call("react", buildJsonObject { put("analysis_id", analysisId); put("item_id", item.id); put("reaction", reaction.name) }, ticket); return
        }
        check(identity)
        val target = AnalysisResultSectionId.entries.firstOrNull { it.wire() == section.wire } ?: return
        val loaded = (hub.load(analysisId) as? RdResult.Success)?.value
        val hubItem = loaded?.sections?.firstOrNull { it.id == target }?.items?.firstOrNull { it.id.equals(item.id, true) } ?: return
        val result = hub.setFeedback(analysisId, target, hubItem, when (reaction) {
            NovaAnalysisReaction.like -> AnalysisItemReaction.Like; NovaAnalysisReaction.dislike -> AnalysisItemReaction.Dislike
            NovaAnalysisReaction.none -> AnalysisItemReaction.None })
        if (result is RdResult.Failure) throw NovaAnalysisException(result.message)
    }

    /** PDF goes through the local renderer and the archive call the product uses; Excel is rendered by the server. */
    suspend fun report(request: NovaAnalysisReportRequest, identity: IsgWorkspaceIdentity, context: IsgWorkspaceContext?): String {
        organization()?.let { ticket ->
            val snapshot = call("detail", buildJsonObject { put("analysis_id", request.analysisId) }, ticket)
            val company = snapshot["company_id"]!!.jsonPrimitive.content
            val title = snapshot["analysis"]!!.jsonObject["title"]!!.jsonPrimitive.content
            val started = call("export", buildJsonObject {
                put("analysis_id", request.analysisId); put("mutation_id", UUID.randomUUID().toString())
                put("format", if (request.format == NovaAnalysisReportFormat.pdf) "pdf" else "xlsx"); put("method", request.method.wire)
                put("attach_company", request.companyId != null)
            }, ticket)
            val job = started["id"]?.jsonPrimitive?.contentOrNull ?: started["row"]?.jsonObject?.get("id")?.jsonPrimitive?.contentOrNull
                ?: throw NovaAnalysisException("unavailable")
            val scope = context ?: throw NovaAnalysisException("unavailable")
            repeat(90) {
                transport.validate(ticket)
                val status = workspace.exportStatus(scope, company, job)
                if (status == "succeeded") return "$title.${if (request.format == NovaAnalysisReportFormat.pdf) "pdf" else "xlsx"}"
                if (status in setOf("failed", "cancelled")) throw NovaAnalysisException("unavailable")
                delay(2_000)
            }
            throw NovaAnalysisException("unavailable")
        }
        check(identity)
        if (request.format == NovaAnalysisReportFormat.excel) {
            return when (val row = reports.generateExcelReport(request.analysisId, request.method.wire, companyId = request.companyId)) {
                is RdResult.Success -> row.value.fileName ?: "rapor.xlsx"
                is RdResult.Failure -> throw NovaAnalysisException(row.message)
            }
        }
        val row = client.postgrest.from("analyses").select { filter { eq("id", request.analysisId) }; limit(1) }.decodeList<AnalysisRow>().firstOrNull()
            ?: throw NovaAnalysisException("unavailable")
        val saved = (findings.fetchFindings(request.analysisId) as? RdResult.Success)?.value ?: throw NovaAnalysisException("unavailable")
        val profile = (profiles.fetchProfile(identity.userId) as? RdResult.Success)?.value
        val images = photos(request.analysisId, null)
        val companyName = request.companyId?.let { companyNames(identity)[it.lowercase()] }
        val generated = withContext(Dispatchers.Default) {
            pdf.generate(PdfReportInput(analysisId = request.analysisId, kind = "risk_analysis", method = request.method.wire, title = row.title,
                canvasLabel = focusLabel(row.canvas) ?: "Genel", createdAt = row.createdAt, findings = saved, companyName = companyName ?: profile?.companyName,
                companyAddress = null, companyLogoBytes = null, preparedByName = profile?.displayName ?: "—", preparedByTitle = profile?.title,
                certificateNumber = profile?.certificateNumber, coverPhotoBytes = images.firstOrNull(), coverPhotoBytesList = images,
                analysisSummary = row.aiSummary, analysisSectorLabel = row.analysisSector?.let(AnalysisSector::fromId)?.titleTr))
        }
        val fileName = PdfReportFileName.build(row.title, request.analysisId, "risk_analysis", request.method.wire)
        return when (val stored = reports.uploadAndRegisterPdfReport(identity.userId, request.analysisId, generated.bytes, fileName, "risk_analysis",
            request.method.wire, row.title, generated.pageCount, request.companyId)) {
            is RdResult.Success -> stored.value.fileName ?: fileName
            is RdResult.Failure -> throw NovaAnalysisException(stored.message)
        }
    }

    /** Files one analysis item as a record on a company; the server returns an existing record on a repeat. */
    suspend fun file(request: NovaAnalysisFileRequest, analysisId: String, identity: IsgWorkspaceIdentity, fallbackCompany: String?): NovaFindingOutcome {
        organization()?.let { ticket ->
            return try {
                val snapshot = call("detail", buildJsonObject { put("analysis_id", analysisId) }, ticket)
                val company = snapshot["company_id"]!!.jsonPrimitive.content
                if (request.companyId != null && !request.companyId.equals(company, true)) return NovaFindingOutcome.Failed("Kayıt oluşturulamadı. Firma erişiminizi kontrol edip tekrar deneyin.")
                val unscored = snapshot["expert_items"]?.jsonArray.orEmpty().any { item ->
                    item.jsonObject["id"]?.jsonPrimitive?.contentOrNull.equals(request.item.id, true) &&
                        item.jsonObject["kind"]?.jsonPrimitive?.contentOrNull == "unscored_finding"
                }
                val kind = when {
                    request.section == NovaAnalysisSectionKind.trainingRecommendations -> "training_item"
                    request.section.isScored || unscored -> "finding"
                    else -> "expert_item"
                }
                val receipt = call("file", buildJsonObject {
                    put("analysis_id", analysisId); put("item_id", request.item.id); put("workplace_id", request.workplaceId?.let(::JsonPrimitive) ?: JsonNull)
                    put("mutation_id", UUID.randomUUID().toString()); put("item_kind", kind); put("record_kind", request.recordKind.name)
                    put("severity", (request.severity?.name ?: request.band)?.let(::JsonPrimitive) ?: JsonNull)
                }, ticket)
                val created = receipt["created"]?.jsonPrimitive?.booleanOrNull == true
                val id = receipt["nonconformity_id"]?.jsonPrimitive?.contentOrNull ?: return NovaFindingOutcome.Failed("Kayıt doğrulanamadı.")
                if (nonconformity.list(NovaCompanyScope(identity, company)).none { it.id.equals(id, true) })
                    return NovaFindingOutcome.Failed("Kayıt oluşturuldu ancak listede doğrulanamadı. Listeyi yenileyip tekrar kontrol edin.")
                if (created) NovaFindingOutcome.Opened else NovaFindingOutcome.AlreadyOpen
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                NovaFindingOutcome.Failed("Kayıt oluşturulamadı. Firma erişiminizi kontrol edip tekrar deneyin.")
            }
        }
        val company = request.companyId ?: fallbackCompany ?: return NovaFindingOutcome.Failed("Bu işlem için yetkiniz yok.")
        val scope = NovaCompanyScope(identity, company)
        val intent = NovaNonconformityIntent(
            origin = if (request.section.isScored) NovaNonconformityIntent.Origin.finding else NovaNonconformityIntent.Origin.expertItem,
            workplaceId = request.workplaceId, title = request.item.title, severity = request.severity,
            riskBand = if (request.section.isScored && request.severity == null) request.band else null,
            findingId = request.item.id.takeIf { request.section.isScored }, sourceMethod = request.sourceMethod.takeIf { request.section.isScored },
            expertItemId = request.item.id.takeIf { !request.section.isScored }, recordKind = request.recordKind,
            hazardDescription = request.item.body.takeIf { !request.section.isScored })
        return try {
            val result = nonconformity.open(scope, intent)
            // A reviewed analysis finding enters the actionable queue as Open; Draft is for unfinished manual entry.
            val filed = if (result.row.state == NovaNonconformityState.draft.name)
                nonconformity.transition(scope, result.row.id, NovaNonconformityState.open, result.row.version, "") else result.row
            if (nonconformity.list(scope).none { it.id == filed.id && it.state == filed.state })
                return NovaFindingOutcome.Failed("Kayıt oluşturuldu ancak listede doğrulanamadı. Listeyi yenileyip tekrar kontrol edin.")
            if (result.alreadyOpen) NovaFindingOutcome.AlreadyOpen else NovaFindingOutcome.Opened
        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: NovaNonconformityException) {
            NovaFindingOutcome.Refused(failure.failure)
        } catch (_: Exception) {
            NovaFindingOutcome.Failed("Bu bulgu için kayıt açılamadı. Aynı işlemi tekrar deneyin.")
        }
    }

    suspend fun filingWorkplaces(identity: IsgWorkspaceIdentity, companyId: String) = nonconformity.filingWorkplaces(NovaCompanyScope(identity, companyId))

    /** The original analysis item behind a filed nonconformity (iOS `RecordFindingPresentation`). */
    data class RecordFinding(val analysisId: String, val item: NovaAnalysisItem, val section: NovaAnalysisSectionKind, val method: NovaRiskMethod,
                             val photo: ByteArray?, val analysisTitle: String, val companyName: String?, val createdOn: String)

    @Serializable private data class FindingLink(@SerialName("analysis_id") val analysisId: String)

    /** Resolves a record born from a photo finding back to that finding, its analysis and its picture (iOS `recordFinding`). */
    suspend fun recordFinding(entry: NovaNonconformityEntry, identity: IsgWorkspaceIdentity, context: IsgWorkspaceContext?,
                              method: NovaRiskMethod): RecordFinding {
        val reference = entry.row.sourceRef?.lowercase()
        organization()?.let { ticket ->
            val analysis = call("source", buildJsonObject { put("record_id", entry.id) }, ticket)["analysis"]?.jsonObject?.get("id")
                ?.jsonPrimitive?.contentOrNull ?: throw NovaAnalysisException("unavailable")
            val detail = detail(analysis, identity, method)
            val (section, item) = detail.sections.asSequence().flatMap { section -> section.items.asSequence().map { section.kind to it } }
                .firstOrNull { (_, item) -> reference != null && (item.id.lowercase() == reference || reference.contains(item.id.lowercase())) }
                ?: throw NovaAnalysisException("unavailable")
            return RecordFinding(analysis, item, section, method, photos(analysis, context).firstOrNull(), detail.title,
                detail.companyName ?: entry.companyName, detail.createdOn)
        }
        check(identity)
        if (!entry.row.cameFromFinding || reference == null) throw NovaAnalysisException("denied")
        val link = client.postgrest.from("findings").select(Columns.list("analysis_id")) { filter { eq("id", reference) }; limit(1) }
            .decodeList<FindingLink>().firstOrNull() ?: throw NovaAnalysisException("unavailable")
        val detail = detail(link.analysisId, identity, method)
        val (section, item) = detail.sections.asSequence().flatMap { section -> section.items.asSequence().map { section.kind to it } }
            .firstOrNull { it.second.id.equals(reference, true) } ?: throw NovaAnalysisException("unavailable")
        val pictures = photos(link.analysisId, null)
        val photo = item.photoIndices.firstOrNull()?.takeIf { it in 1..pictures.size }?.let { pictures[it - 1] } ?: pictures.firstOrNull()
        return RecordFinding(link.analysisId, item, section, method, photo, detail.title, entry.companyName, detail.createdOn)
    }

    /** Where a photo analysis is on its way (iOS `AnalysisProgressUpdate`). */
    enum class Progress { uploadingPhotos, creatingAnalysis, queued, analyzing }

    /** The expert's plan tier, so a focus it does not include is shown locked rather than hidden. */
    suspend fun tier(identity: IsgWorkspaceIdentity) = (profiles.fetchProfile(identity.userId) as? RdResult.Success)?.value?.tier

    /**
     * Runs one photo analysis through the pipeline the product ships and returns the finished analysis id. An
     * organization ticket files the photos into the company and asks the workspace worker; a personal account
     * creates, uploads, submits and polls its own analysis.
     */
    suspend fun run(identity: IsgWorkspaceIdentity, context: IsgWorkspaceContext?, companyId: String?, images: List<ByteArray>, focuses: List<String>,
                    sector: String?, progress: (Progress) -> Unit): String {
        if (images.isEmpty() || images.size > 20) throw NovaAnalysisException("validation")
        organization()?.let { ticket ->
            val company = companyId ?: throw NovaAnalysisException("validation")
            val scope = context ?: throw NovaAnalysisException("unavailable")
            progress(Progress.uploadingPhotos)
            val assets = images.mapIndexed { index, bytes ->
                transport.validate(ticket)
                val draft = NovaFileDraft(title = "Analiz fotoğrafı ${index + 1}", category = "inspection_report",
                    fileName = "analiz-${UUID.randomUUID()}.jpg", fileExtension = "jpg", bytes = bytes.size, sha256 = NovaFileDraft.sha256(bytes))
                val entry = files.file(identity, company, draft, bytes)
                if (!entry.state.isFiled) throw NovaAnalysisException("inspection")
                entry.assetId ?: throw NovaAnalysisException("inspection")
            }
            progress(Progress.creatingAnalysis)
            val started = call("submit", buildJsonObject {
                put("company_id", company); put("mutation_id", UUID.randomUUID().toString())
                put("asset_ids", JsonArray(assets.map(::JsonPrimitive))); put("focus_ids", JsonArray(focuses.map(::JsonPrimitive)))
                put("sector", sector?.let(::JsonPrimitive) ?: JsonNull)
            }, ticket)
            val job = started["id"]?.jsonPrimitive?.contentOrNull ?: throw NovaAnalysisException("unavailable")
            repeat(180) {
                transport.validate(ticket)
                val (status, analysis) = workspace.photoAnalysisJob(scope, company, job)
                if (status == "succeeded" && analysis != null) return analysis
                if (status in setOf("failed", "cancelled")) throw NovaAnalysisException("failed")
                progress(if (status == "running") Progress.analyzing else Progress.queued)
                delay(2_000)
            }
            throw NovaAnalysisException("timeout")
        }
        check(identity)
        val profile = (profiles.fetchProfile(identity.userId) as? RdResult.Success)?.value ?: throw NovaAnalysisException("unavailable")
        val localization = profile.safetyProfileId?.let(RdClientMetadata::localizationForSafetyProfile)
        val language = profile.appLanguage?.takeIf { it == "tr" || it == "en" } ?: localization?.appLanguage ?: RdClientMetadata.APP_LANGUAGE
        val method = profile.preferredMethod?.takeIf { it == "fine_kinney" || it == "matrix_5x5" } ?: RdClientMetadata.DEFAULT_RISK_METHOD
        val chosenSector = sector?.let(AnalysisSector::fromId)
        val ordered = focuses.sorted().ifEmpty { listOf("general") }
        progress(Progress.creatingAnalysis)
        val analysis = when (val created = analyses.createAnalysis(CreateAnalysisRequest(identity.userId, chosenSector?.titleTr ?: "Adsız analiz",
            ordered.first(), chosenSector, companyId, clientSubmissionId = UUID.randomUUID().toString(), primaryMethod = method))) {
            is RdResult.Success -> created.value
            is RdResult.Failure -> throw NovaAnalysisException(created.message)
        }
        progress(Progress.uploadingPhotos)
        val paths = images.mapIndexed { index, bytes ->
            when (val uploaded = photos.uploadPhoto(identity.userId, analysis, index + 1, bytes)) {
                is RdResult.Success -> uploaded.value
                is RdResult.Failure -> throw NovaAnalysisException(uploaded.message)
            }
        }
        progress(Progress.queued)
        val submitted = analyses.submitAnalyze(analysis, ordered.first(), ordered, "standard", chosenSector, paths, language, language,
            profile.preferredContentLocale ?: localization?.contentLocale ?: RdClientMetadata.CONTENT_LOCALE,
            profile.workJurisdictionCountry ?: localization?.workJurisdictionCountry ?: RdClientMetadata.WORK_JURISDICTION_COUNTRY,
            profile.safetyProfileId ?: localization?.safetyProfileId ?: RdClientMetadata.SAFETY_PROFILE_ID,
            profile.safetyProfileVersion ?: localization?.safetyProfileVersion ?: RdClientMetadata.SAFETY_PROFILE_VERSION, method)
        if (submitted is RdResult.Failure && (analyses.fetchAnalysisStatus(analysis) as? RdResult.Success)?.value !in setOf("queued", "processing", "completed"))
            throw NovaAnalysisException(submitted.message)
        progress(Progress.analyzing)
        return when (val status = analyses.pollAnalysisStatus(analysis, images.size)) {
            AnalysisStatus.Completed -> analysis
            is AnalysisStatus.Failed -> throw NovaAnalysisException(status.message ?: "failed")
            else -> throw NovaAnalysisException("timeout")
        }
    }

    companion object {
        private val display = DateTimeFormatter.ofPattern("d MMMM yyyy · HH:mm", Locale.forLanguageTag("tr-TR"))

        fun instant(value: String?): Instant? = value?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }

        /** A stamp neither parser understands is shown as it came rather than as a guess. */
        fun day(value: String?): String = value?.let { raw -> instant(raw)?.atZone(ZoneId.of("Europe/Istanbul"))?.format(display) ?: raw }.orEmpty()

        fun focusLabel(canvas: String): String? = canvas.split(",").firstNotNullOfOrNull { raw -> AnalysisCanvas.all.firstOrNull { it.id == raw.trim() }?.title }
    }
}
