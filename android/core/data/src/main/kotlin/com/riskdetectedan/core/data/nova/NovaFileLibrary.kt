package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTicket
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.storage.storage
import io.ktor.http.ContentType
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Where one filed document has got to; always the server's word. */
enum class NovaFileState(val wire: String) {
    pending("pending"), uploaded("uploaded"), scanning("scanning"), clean("clean"), rejected("rejected"),
    scanFailed("scan_failed"), promoted("promoted"), expired("expired");
    val isFiled: Boolean get() = this == promoted
    val isWorking: Boolean get() = this in setOf(pending, uploaded, scanning, clean)
    val isStopped: Boolean get() = this in setOf(rejected, scanFailed, expired)
    val title: String get() = when (this) {
        pending -> "Yükleniyor"; uploaded, scanning -> "Denetleniyor"; clean -> "Arşivleniyor"; promoted -> "Dosyada"
        rejected -> "Kabul edilmedi"; scanFailed -> "Denetlenemedi"; expired -> "Süre doldu"
    }
    companion object { fun of(wire: String) = entries.firstOrNull { it.wire == wire } }
}

/** The four counters the archive shows; the same words are server filter values. */
enum class NovaFileGroup(val title: String, val footer: String, val symbol: String, val states: List<NovaFileState>) {
    filed("Dosyada", "arşivde", "checkmark.circle", listOf(NovaFileState.promoted)),
    working("İşleniyor", "denetimde", "arrow.up.circle", listOf(NovaFileState.pending, NovaFileState.uploaded, NovaFileState.scanning, NovaFileState.clean)),
    rejected("Kabul edilmedi", "içerik nedeniyle", "exclamationmark.triangle", listOf(NovaFileState.rejected)),
    unchecked("Denetlenemedi", "denetim bitmedi", "questionmark.circle", listOf(NovaFileState.scanFailed, NovaFileState.expired));
    companion object { fun of(state: NovaFileState) = entries.firstOrNull { state in it.states } ?: unchecked }
}

data class NovaFileCategory(val code: String, val ordinal: Int, val section: String)
data class NovaFileAcceptance(val purpose: String, val extensions: List<String>, val maxBytes: Int, val limitApproved: Boolean)
data class NovaFileAssurance(val scanners: List<String> = emptyList(), val malwareScanningAvailable: Boolean = false)

data class NovaFileEntry(
    val id: String, val assetId: String?, val companyId: String?, val companyName: String?, val category: String,
    val section: String?, val title: String, val fileName: String, val note: String?, val version: Int,
    val state: NovaFileState, val rejectionCode: String?, val fileExtension: String, val declaredBytes: Int,
    val receivedBytes: Int?, val detectedType: String?, val uploadBucket: String?, val uploadPath: String?,
    val downloadBucket: String?, val downloadPath: String?, val scanner: String?, val scanFinding: String?,
    val assurance: String?, val malwareScanned: Boolean, val createdAt: String?, val tags: List<String>,
) {
    val canDownload: Boolean get() = downloadBucket != null && downloadPath != null
    val bytes: Int get() = receivedBytes ?: declaredBytes
}

data class NovaFileCompanySummary(val id: String, val name: String, val total: Int, val counts: Map<NovaFileState, Int>) {
    fun count(group: NovaFileGroup) = group.states.sumOf { counts[it] ?: 0 }
}

data class NovaFileLibraryPage(
    val counts: Map<NovaFileState, Int> = emptyMap(), val companies: List<NovaFileCompanySummary> = emptyList(),
    val categoryCounts: Map<String, Map<NovaFileState, Int>> = emptyMap(), val rows: List<NovaFileEntry> = emptyList(),
    val total: Int = 0, val hasMore: Boolean = false, val limit: Int = 10, val offset: Int = 0,
    val assurance: NovaFileAssurance = NovaFileAssurance(),
) {
    fun count(group: NovaFileGroup) = group.states.sumOf { counts[it] ?: 0 }
    val filed: Int get() = counts[NovaFileState.promoted] ?: 0
    /** What one company heading carries, summed over its own categories. */
    fun counts(forCategories: List<String>): Map<NovaFileState, Int> {
        val result = mutableMapOf<NovaFileState, Int>()
        forCategories.forEach { category -> categoryCounts[category]?.forEach { (state, value) -> result[state] = (result[state] ?: 0) + value } }
        return result
    }
}

data class NovaFileQuery(val query: String = "", val state: String? = null, val company: String? = null,
                         val category: String? = null, val limit: Int = 10, val offset: Int = 0)

/** What the file form collects before an upload is opened. */
data class NovaFileDraft(val tags: String = "", val title: String = "", val category: String? = null, val note: String = "",
                         val fileName: String = "", val fileExtension: String = "", val bytes: Int = 0, val sha256: String = "") {
    val parsedTags: List<String> get() = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSortedSet().toList()
    val isReady: Boolean get() = parsedTags.size <= 12 && parsedTags.all { it.length <= 40 } && category != null &&
        title.isNotBlank() && fileExtension.isNotEmpty() && bytes > 0 && sha256.length == 64

    companion object {
        fun sha256(data: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
    }
}

enum class NovaFileFailure(val message: String) {
    denied("Bu firmanın dosyalarına erişim yok."),
    validation("Bilgiler eksik veya geçersiz."),
    versionConflict("Kayıt başka bir yerden değişmiş. Sayfayı yenileyip tekrar deneyin."),
    unavailable("Dosya servisi şu anda kullanılamıyor."),
    planRequired("Dosya eklemek için Plus veya Pro plan gerekiyor."),
    conflict("Bu işlem farklı bir içerikle zaten kaydedilmiş."),
    unsupportedFormat("Bu dosya türü kabul edilmiyor."),
    tooLarge("Dosya boyutu sınırın dışında."),
    uploadFailed("Dosya gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin."),
    notCancellable("Bu dosya arşive alınmış; iptal edilemez. Kaldırmak için arşivden çıkarın."),
    // The upload stays where it really is; nothing reports it cleared.
    inspectionUnavailable("Denetim şu anda çalıştırılamadı. Dosya arşive alınmadı; kaydın üzerinden tekrar deneyebilirsiniz."),
}

class NovaFileException(val failure: NovaFileFailure) : Exception(failure.name)

/**
 * The file archive (iOS `NovaFileLibraryService`). An upload is three steps that
 * are never collapsed: the server opens an intent with a write-only path, the
 * device puts the bytes there, and a worker the device cannot impersonate
 * decides whether they leave quarantine.
 */
@Singleton
class NovaFileLibraryService @Inject constructor(private val client: SupabaseClient,
                                                 private val transport: NovaExpertTransport) {
    @Serializable private data class EntryRow(
        val id: String, @SerialName("asset_id") val assetId: String? = null, @SerialName("company_id") val companyId: String? = null,
        @SerialName("company_name") val companyName: String? = null, val category: String, val section: String? = null,
        val title: String, @SerialName("file_name") val fileName: String, val note: String? = null, val tags: List<String>? = null,
        val version: Int, val state: String, @SerialName("rejection_code") val rejectionCode: String? = null,
        @SerialName("extension") val fileExtension: String? = null, @SerialName("declared_bytes") val declaredBytes: Int,
        @SerialName("received_bytes") val receivedBytes: Int? = null, @SerialName("detected_type") val detectedType: String? = null,
        @SerialName("upload_bucket") val uploadBucket: String? = null, @SerialName("upload_path") val uploadPath: String? = null,
        @SerialName("download_bucket") val downloadBucket: String? = null, @SerialName("download_path") val downloadPath: String? = null,
        val scanner: String? = null, @SerialName("scan_finding") val scanFinding: String? = null, val assurance: String? = null,
        @SerialName("malware_scanned") val malwareScanned: Boolean = false, @SerialName("created_at") val createdAt: String? = null,
    )
    @Serializable private data class CategoryRow(val code: String, val ordinal: Int, val section: String)
    @Serializable private data class AcceptRow(val purpose: String, val extensions: List<String>, @SerialName("max_bytes") val maxBytes: Int,
                                               @SerialName("limit_approved") val limitApproved: Boolean)
    @Serializable private data class ScannerRow(val scanner: String, @SerialName("detects_malware") val detectsMalware: Boolean)
    @Serializable private data class CatalogEnvelope(val categories: List<CategoryRow>, val accepts: List<AcceptRow>,
                                                     val scanners: List<ScannerRow>,
                                                     @SerialName("malware_scanning_available") val malwareScanningAvailable: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<EntryRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
                                                  @SerialName("category_counts") val categoryCounts: Map<String, Map<String, Int>>,
                                                  val total: Int, @SerialName("has_more") val hasMore: Boolean, val limit: Int, val offset: Int,
                                                  @SerialName("malware_scanning_available") val malwareScanningAvailable: Boolean)
    @Serializable private data class DetailEnvelope(val row: EntryRow)
    @Serializable private data class MutationEnvelope(@SerialName("entry_id") val entryId: String, val row: EntryRow)

    data class Catalogue(val categories: List<NovaFileCategory>, val accepts: List<NovaFileAcceptance>, val assurance: NovaFileAssurance)

    private fun check(identity: IsgWorkspaceIdentity, ticket: NovaExpertTicket?) {
        if (transport.capture() !== ticket || transport.identityNow() != identity) throw NovaFileException(NovaFileFailure.denied)
    }

    private suspend fun rpc(function: String, args: JsonObject, ticket: NovaExpertTicket?): JsonElement = try {
        transport.execute(function, args, ticket)
    } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive()
        throw NovaFileException(when {
            failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaFileFailure.unavailable
            failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaFileFailure.denied
            failure.code == "PAID_PLAN_REQUIRED" -> NovaFileFailure.planRequired
            failure.code == "UNSUPPORTED_FORMAT" -> NovaFileFailure.unsupportedFormat
            failure.code == "SIZE_LIMIT" -> NovaFileFailure.tooLarge
            failure.code == "UPLOAD_NOT_CANCELLABLE" -> NovaFileFailure.notCancellable
            failure.code == "VERSION_CONFLICT" -> NovaFileFailure.versionConflict
            failure.code == "IDEMPOTENCY_CONFLICT" -> NovaFileFailure.conflict
            failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaFileFailure.validation
            else -> NovaFileFailure.unavailable
        })
    }

    private fun <T> JsonElement.decode(serializer: kotlinx.serialization.KSerializer<T>): T = try {
        novaJson.decodeFromJsonElement(serializer, this)
    } catch (_: Exception) { throw NovaFileException(NovaFileFailure.unavailable) }

    private fun states(raw: Map<String, Int>): Map<NovaFileState, Int> =
        raw.mapNotNull { (key, value) -> NovaFileState.of(key)?.let { it to value } }.toMap()

    /** An unknown state word reads as a stopped upload rather than a calm one. */
    private fun entry(row: EntryRow) = NovaFileEntry(row.id, row.assetId, row.companyId, row.companyName, row.category, row.section,
        row.title, row.fileName, row.note, row.version, NovaFileState.of(row.state) ?: NovaFileState.scanFailed, row.rejectionCode,
        row.fileExtension.orEmpty(), row.declaredBytes, row.receivedBytes, row.detectedType, row.uploadBucket, row.uploadPath,
        row.downloadBucket, row.downloadPath, row.scanner, row.scanFinding, row.assurance, row.malwareScanned, row.createdAt,
        row.tags.orEmpty())

    private suspend fun read(arguments: Map<String, JsonElement>, ticket: NovaExpertTicket?): JsonElement {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"),
            "p_query" to JsonNull, "p_category" to JsonNull, "p_state" to JsonNull, "p_id" to JsonNull,
            "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        return rpc("isg_pilot_file_library_read_v2", JsonObject(payload), ticket)
    }

    suspend fun catalogue(identity: IsgWorkspaceIdentity): Catalogue {
        val ticket = transport.capture(); check(identity, ticket)
        val envelope = read(mapOf("p_kind" to JsonPrimitive("catalog")), ticket).decode(CatalogEnvelope.serializer())
        check(identity, ticket)
        return Catalogue(envelope.categories.map { NovaFileCategory(it.code, it.ordinal, it.section) },
            envelope.accepts.map { NovaFileAcceptance(it.purpose, it.extensions, it.maxBytes, it.limitApproved) },
            NovaFileAssurance(envelope.scanners.map { it.scanner }, envelope.malwareScanningAvailable))
    }

    suspend fun library(identity: IsgWorkspaceIdentity, query: NovaFileQuery = NovaFileQuery()): NovaFileLibraryPage {
        val ticket = transport.capture(); check(identity, ticket)
        val trimmed = query.query.trim()
        val envelope = read(mapOf("p_company" to (query.company?.let(::JsonPrimitive) ?: JsonNull),
            "p_query" to (if (trimmed.isEmpty()) JsonNull else JsonPrimitive(trimmed)),
            "p_category" to (query.category?.let(::JsonPrimitive) ?: JsonNull),
            "p_state" to (query.state?.let(::JsonPrimitive) ?: JsonNull),
            "p_limit" to JsonPrimitive(query.limit), "p_offset" to JsonPrimitive(query.offset)), ticket)
            .decode(ListEnvelope.serializer())
        check(identity, ticket)
        return NovaFileLibraryPage(states(envelope.counts),
            envelope.companies.map { NovaFileCompanySummary(it.id, it.name, it.total, states(it.counts)) },
            envelope.categoryCounts.mapValues { states(it.value) }, envelope.rows.map(::entry), envelope.total,
            envelope.hasMore, envelope.limit, envelope.offset, NovaFileAssurance(malwareScanningAvailable = envelope.malwareScanningAvailable))
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, entryId: String): NovaFileEntry {
        val ticket = transport.capture(); check(identity, ticket)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(entryId)), ticket).decode(DetailEnvelope.serializer()).row
        check(identity, ticket)
        return entry(row)
    }

    private suspend fun mutate(company: String?, action: String, payload: JsonObject, ticket: NovaExpertTicket?,
                               mutationId: String = UUID.randomUUID().toString()): NovaFileEntry =
        entry(rpc("isg_pilot_file_library_mutate_v2", buildJsonObject {
            putId("p_company", company); put("p_action", action); put("p_operation", UUID.randomUUID().toString())
            put("p_mutation", mutationId); put("p_payload", payload)
        }, ticket).decode(MutationEnvelope.serializer()).row)

    /** Opens, uploads and asks for inspection; never reports a file before the server does. */
    suspend fun file(identity: IsgWorkspaceIdentity, company: String?, draft: NovaFileDraft, data: ByteArray,
                     mutationId: String = UUID.randomUUID().toString(), progress: ((NovaFileEntry) -> Unit)? = null): NovaFileEntry {
        val ticket = transport.capture(); check(identity, ticket)
        val category = draft.category
        if (!draft.isReady || category == null) throw NovaFileException(NovaFileFailure.validation)
        val opened = mutate(company, "open_upload", buildJsonObject {
            put("title", draft.title.trim()); put("category", category); put("file_name", draft.fileName.trim())
            putJsonArray("tags") { draft.parsedTags.forEach { add(it) } }
            putId("note", draft.note.trim().ifEmpty { null })
            put("extension", draft.fileExtension.lowercase()); put("bytes", draft.bytes); put("sha256", draft.sha256)
        }, ticket, mutationId)
        progress?.invoke(opened)
        check(identity, ticket)
        // A replayed open has already been uploaded; the bucket refuses a second put.
        val bucket = opened.uploadBucket
        val path = opened.uploadPath
        if (bucket == null || path == null) {
            if (opened.state.isWorking || opened.state.isFiled) return opened
            throw NovaFileException(NovaFileFailure.uploadFailed)
        }
        try {
            client.storage.from(bucket).upload(path, data) {
                upsert = false
                contentType = ContentType.parse(contentType(draft.fileExtension))
            }
        } catch (cancelled: CancellationException) { throw cancelled
        } catch (_: Exception) { throw NovaFileException(NovaFileFailure.uploadFailed) }
        check(identity, ticket)
        inspect(opened.id, ticket)
        check(identity, ticket)
        return detail(identity, opened.id)
    }

    private suspend fun inspect(entryId: String, ticket: NovaExpertTicket?) {
        try {
            client.functions.invoke("isg-file-inspect", buildJsonObject {
                put("entry_id", entryId.lowercase()); putId("workspace_id", ticket?.access?.workspaceId?.lowercase())
            })
        } catch (cancelled: CancellationException) { throw cancelled
        } catch (_: Exception) {
            // The upload keeps whatever state it really reached.
            throw NovaFileException(NovaFileFailure.inspectionUnavailable)
        }
    }

    suspend fun rename(identity: IsgWorkspaceIdentity, target: NovaFileEntry, title: String, category: String, note: String): NovaFileEntry {
        val ticket = transport.capture(); check(identity, ticket)
        val result = mutate(target.companyId, "rename_entry", buildJsonObject {
            put("entry_id", target.id); put("expected_version", target.version); put("title", title.trim()); put("category", category)
            putJsonArray("tags") { target.tags.forEach { add(it) } }; putId("note", note.trim().ifEmpty { null })
        }, ticket)
        check(identity, ticket); return result
    }

    suspend fun archive(identity: IsgWorkspaceIdentity, target: NovaFileEntry) {
        val ticket = transport.capture(); check(identity, ticket)
        mutate(target.companyId, "archive_entry", buildJsonObject { put("entry_id", target.id); put("expected_version", target.version) }, ticket)
    }

    /** Abandons an upload that never became a file; a filed document is archived instead. */
    suspend fun cancel(identity: IsgWorkspaceIdentity, target: NovaFileEntry) {
        val ticket = transport.capture(); check(identity, ticket)
        mutate(target.companyId, "cancel_upload", buildJsonObject { put("entry_id", target.id); put("expected_version", target.version) }, ticket)
    }

    /** Retries inspection of an upload still on its way; it cannot change a verdict. */
    suspend fun recheck(identity: IsgWorkspaceIdentity, target: NovaFileEntry): NovaFileEntry {
        val ticket = transport.capture(); check(identity, ticket)
        inspect(target.id, ticket)
        return detail(identity, target.id)
    }

    suspend fun contents(identity: IsgWorkspaceIdentity, target: NovaFileEntry): ByteArray {
        val bucket = target.downloadBucket ?: throw NovaFileException(NovaFileFailure.validation)
        val path = target.downloadPath ?: throw NovaFileException(NovaFileFailure.validation)
        return download(identity, bucket, path)
    }

    suspend fun download(identity: IsgWorkspaceIdentity, bucket: String, path: String): ByteArray {
        val ticket = transport.capture(); check(identity, ticket)
        val bytes = try { client.storage.from(bucket).downloadAuthenticated(path) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { throw NovaFileException(NovaFileFailure.unavailable) }
        check(identity, ticket); return bytes
    }

    /** Files evidence photos before a record opens, so the server only attaches clean, owned assets. */
    suspend fun fileEvidence(identity: IsgWorkspaceIdentity, company: String, jpegs: List<ByteArray>, title: String,
                             category: String): List<String> = jpegs.mapNotNull { data ->
        val draft = NovaFileDraft(title = title, category = category, fileName = "uygunsuzluk-${UUID.randomUUID().toString().take(8)}.jpg",
            fileExtension = "jpg", bytes = data.size, sha256 = NovaFileDraft.sha256(data))
        runCatching { file(identity, company, draft, data).assetId }.getOrNull()
    }

    companion object {
        /** Only a transfer hint; the inspector decides the real type from the bytes. */
        fun contentType(fileExtension: String): String = when (fileExtension.lowercase()) {
            "pdf" -> "application/pdf"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "csv" -> "text/csv"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "avif" -> "image/avif"
            "heic", "heif" -> "image/heic"
            else -> "application/octet-stream"
        }
    }
}
