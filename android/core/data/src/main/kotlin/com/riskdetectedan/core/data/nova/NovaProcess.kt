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

/** One field of a process record form (iOS `NovaProcessField`). */
data class NovaProcessField(val id: String, val title: String, val type: String = "text", val choices: Map<String, String> = emptyMap(),
                            val required: Boolean = false)

/** A process record kind and its form (iOS `NovaProcessKind`). */
data class NovaProcessKind(val code: String, val title: String, val fields: List<NovaProcessField>, val child: String? = null, val parentKey: String? = null) {
    val help: String get() = when (code) {
        "annual_work_plan" -> "Yıllık planı açın; faaliyetleri, sorumluları ve gerçekleşme durumunu takip edin."
        "annual_work_item" -> "Faaliyeti ve tarihini kaydedin; gerçekleştiğinde durumunu güncelleyin."
        "board" -> "Gerçekleşen toplantının gündemini ve katılımcılarını ekleyin; kararlarını takip edin."
        "board_decision" -> "Her kararı ayrı ekleyin; sorumlusunu ve varsa tamamlanma tarihini belirtin."
        "completed_drill" -> "Gerçekleşen tatbikatı kaydedin; senaryo, süre, fotoğraf ve raporunu birlikte takip edin."
        "personnel_certificate" -> "Personelin belgesini kaydedin. Dosya isteğe bağlıdır; geçerlilik tarihi firma takibine yansır."
        "approved_notebook" -> "Onaylı defter sayfasının fotoğrafını firmanın arşivine ekleyin; dilediğinizde açıp indirin."
        "site_visit" -> "Ziyaret tarihini ve yaptığınız işlemleri kaydedin; görüşülen kişiyi isteğe bağlı ekleyin."
        "site_observation" -> "Ziyaretteki gözlemi veya aksiyonu kaydedin; ilgili kayda bağlayabilirsiniz."
        "contractor", "contractor_engagement" -> "Firmanın taşeronlarını ve birlikte yürütülen işleri kaydedin."
        "work_permit" -> "Çalışmayı, ilgili kişileri ve alınacak önlemleri belirtin; formu indirin."
        else -> "Firmanın kaydını ekleyin, bilgilerini düzenleyin ve gerektiğinde çıktısını alın."
    }
    val emptyTitle: String get() = when (code) {
        "katip_contract" -> "Henüz İSG-KATİP sözleşmesi yok"; "annual_work_plan" -> "Henüz yıllık çalışma planı yok"
        "board" -> "Henüz kurul veya toplantı kaydı yok"; "site_visit" -> "Henüz saha ziyareti kaydı yok"
        "work_permit" -> "Henüz çalışma izni formu yok"; "contractor" -> "Henüz taşeron veya dış firma kaydı yok"
        else -> "Henüz kayıt yok"
    }
    val emptyMessage: String get() = when (code) {
        "katip_contract" -> "Sözleşmeyi ekleyerek hizmet kapsamını, süresini ve sözleşme dosyasını firma bazında takip edebilirsiniz."
        "annual_work_plan" -> "Yıllık planı ekleyerek faaliyetleri, sorumluları ve gerçekleşme durumlarını tek yerden takip edebilirsiniz."
        "board" -> "Gerçekleşen toplantıyı ekleyerek gündemi, katılımcıları ve kararları birlikte izleyebilirsiniz."
        "site_visit" -> "Saha ziyaretini ekleyerek yapılan işlemleri, notları ve kanıtları dijital ortamda saklayabilirsiniz."
        "work_permit" -> "Çalışma izni formunu ekleyerek işi, tarafları ve alınacak önlemleri kayıt altına alabilirsiniz."
        "contractor" -> "Taşeron veya dış firmayı ekleyerek yürütülen işleri ve iletişim bilgilerini takip edebilirsiniz."
        else -> "Yeni kayıt ekleyerek bu süreci dijital ortamda düzenli biçimde takip edebilirsiniz."
    }

    companion object {
        private fun f(key: String, title: String, type: String = "text", required: Boolean = false, choices: Map<String, String> = emptyMap()) =
            NovaProcessField(key, title, type, choices, required)

        fun get(code: String): NovaProcessKind {
            val workplace = f("workplace_id", "İşyeri", "workplaces", true)
            return when (code) {
                "katip_contract" -> NovaProcessKind(code, "İSG-KATİP Sözleşmeleri", listOf(workplace, f("counterparty", "Sözleşme tarafı", "text", true),
                    f("expert_contact", "Uzman / iletişim", "text", true), f("scope", "Hizmet kapsamı", "text", true), f("starts_on", "Başlangıç", "date", true),
                    f("ends_before", "Bitiş (hariç)", "date"), f("declared_monthly_minutes", "Beyan edilen aylık dakika", "number"), f("declared_note", "Hizmet notu"),
                    f("asset_id", "Sözleşme dosyası", "file")))
                "annual_work_plan" -> NovaProcessKind(code, "Yıllık Çalışma Planı", listOf(workplace, f("plan_year", "Plan yılı", "number", true)), child = "annual_work_item")
                "annual_work_item" -> NovaProcessKind(code, "Plan Faaliyetleri", listOf(f("activity", "Faaliyet / hedef", "multiline", true), f("responsible_contact", "Sorumlu"),
                    f("planned_on", "Planlanan tarih", "date", true),
                    f("state", "Durum", "choice", true, linkedMapOf("planned" to "Planlandı", "performed" to "Gerçekleşti", "carried_over" to "Ertelendi", "cancelled" to "İptal")),
                    f("performed_on", "Gerçekleşme tarihi", "date"), f("carry_over_reason", "Erteleme gerekçesi", "multiline")), parentKey = "plan_id")
                "board" -> NovaProcessKind(code, "Kurul ve Toplantılar", listOf(workplace, f("applicability", "Toplantı türü", "choice", true, mapOf("mandatory" to "Mevzuat zorunlu toplantı")),
                    f("agenda", "Gündem maddeleri", "lines", true), f("initial_decisions", "Alınan kararlar", "lines"), f("planned_on", "Toplantı tarihi", "date", true),
                    f("state", "Durum", "choice", true, linkedMapOf("held" to "Gerçekleşti", "cancelled" to "İptal")), f("held_on", "Gerçekleşme tarihi", "date"),
                    f("attendance", "Katılımcılar", "employees"), f("cancelled_reason", "İptal gerekçesi", "multiline"), f("minutes_asset_id", "Toplantı dosyası", "file")),
                    child = "board_decision")
                "board_decision" -> NovaProcessKind(code, "Kararlar ve Takip", listOf(f("decision_no", "Karar no", "number", true), f("decision_text", "Karar / aksiyon", "multiline", true),
                    f("responsible_contact", "Sorumlu"), f("due_on", "Termin", "date"),
                    f("state", "Durum", "choice", true, linkedMapOf("open" to "Açık", "done" to "Tamamlandı", "cancelled" to "İptal"))), parentKey = "meeting_id")
                "completed_drill" -> NovaProcessKind(code, "Tatbikatlar", listOf(workplace, f("held_on", "Tatbikat tarihi", "date", true),
                    f("drill_type", "Tatbikat türü", "choice", true, linkedMapOf("emergency" to "Acil durum", "fire" to "Yangın")),
                    f("announcement", "Haber durumu", "choice", true, linkedMapOf("announced" to "Haberli", "unannounced" to "Habersiz")), f("bekra", "BEKRA tatbikatı", "bool"),
                    f("duration_minutes", "Tamamlanma süresi (dakika)", "number"), f("scenario", "Senaryo", "multiline", true), f("note", "Notlar", "multiline"),
                    f("photo_ids", "Fotoğraflar · en fazla 10", "photos"), f("asset_id", "Tatbikat raporu · PDF", "pdf"), f("due_override", "Takip tarihini değiştir", "bool"),
                    f("valid_until", "Sonraki tatbikat tarihi", "date")))
                "personnel_certificate" -> NovaProcessKind(code, "Personel Belgeleri", listOf(f("employee_id", "Personel", "employee", true),
                    f("certificate_kind", "Belge türü", "choice", true, linkedMapOf("first_aid" to "İlk yardım", "myk" to "MYK", "custom" to "Diğer")),
                    f("title", "Belge adı", "text", true), f("issued_on", "Düzenleme tarihi", "date", true), f("due_override", "Geçerlilik tarihini değiştir", "bool"),
                    f("valid_until", "Geçerlilik tarihi", "date"), f("asset_id", "Belge dosyası · isteğe bağlı", "file"), f("note", "Not", "multiline")))
                "approved_notebook" -> NovaProcessKind(code, "Onaylı Defter", listOf(f("title", "Başlık", "text", true), f("asset_id", "Defter görseli", "photo", true), f("note", "Not", "multiline")))
                "site_visit" -> NovaProcessKind(code, "Saha Ziyaretleri", listOf(workplace, f("visited_on", "Ziyaret tarihi", "date", true),
                    f("expert_note", "Ziyaret notu", "multiline", true), f("location_note", "Ziyaret yeri"), f("responsible_contact", "Görüşülen kişi"),
                    f("duration_minutes", "Ziyaret süresi (dakika)", "number"), f("visit_asset_id", "Ziyaret fotoğrafı", "photo")), child = "site_observation")
                "site_observation" -> NovaProcessKind(code, "Gözlemler", listOf(f("note", "Gözlem / aksiyon", "multiline", true), f("external_ref", "Uygunsuzluk / kanıt referansı")),
                    parentKey = "visit_id")
                "work_permit" -> NovaProcessKind(code, "Çalışma İzni Formları", listOf(workplace,
                    f("template_code", "Form türü", "choice", true, linkedMapOf("general" to "Genel çalışma", "hot_work" to "Sıcak iş", "work_at_height" to "Yüksekte çalışma",
                        "confined_space" to "Kapalı alan", "electrical" to "Elektrik işi")),
                    f("job_description", "İş tanımı", "multiline", true), f("planned_on", "Planlanan tarih", "date", true), f("work_location", "Çalışma yeri"),
                    f("starts_at", "Başlangıç saati", "datetime"), f("ends_at", "Bitiş saati", "datetime"), f("parties", "İlgili personeller", "employees"),
                    f("risk_precautions", "Riskler, önlemler ve sorumlular", "multiline")))
                "contractor" -> NovaProcessKind(code, "Taşeron ve Dış Firmalar", listOf(f("code", "Firma kodu", "text", true), f("name", "Ticari ad", "text", true),
                    f("relationship", "İlişki", "choice", true, linkedMapOf("subcontractor" to "Alt işveren (beyan)", "contractor" to "Yüklenici", "supplier" to "Tedarikçi", "other" to "Diğer")),
                    f("contact", "Yetkili / iletişim"), f("identifiers", "Vergi / işyeri tanımlayıcısı"), f("notes", "Notlar", "multiline")), child = "contractor_engagement")
                else -> NovaProcessKind("contractor_engagement", "İş ve Sözleşmeler", listOf(f("organization_id", "Dış firma", "organizations", true), workplace,
                    f("starts_on", "Başlangıç", "date", true), f("ends_before", "Bitiş (hariç)", "date"), f("description", "Yapılan iş", "multiline", true)))
            }
        }

        fun referenceTitle(kind: String) = when (kind) {
            "training_record" -> "Gerçekleşen eğitim"; "equipment_inspection" -> "Ekipman kontrolü"; "nonconformity" -> "Uygunsuzluk"
            "checklist_run" -> "Tamamlanan kontrol"; else -> get(kind).title
        }
    }
}

/** A JSON value in a process record, read the way the iOS `NovaModuleValue.text` reads it. */
fun JsonElement?.novaText(): String = when (this) {
    is JsonPrimitive -> when {
        this is JsonNull -> ""
        isString -> content
        booleanOrNull != null -> if (boolean) "true" else "false"
        else -> doubleOrNull?.let { if (it == Math.rint(it)) it.toLong().toString() else it.toString() } ?: content
    }
    else -> ""
}

/** The wire form every scalar travels as: a string, as iOS `NovaModuleValue.rpc` sends it. */
fun JsonElement.novaRpc(): JsonElement = when (this) {
    is JsonNull -> JsonNull
    is JsonPrimitive -> JsonPrimitive(novaText())
    is JsonArray -> JsonArray(map { it.novaRpc() })
    is JsonObject -> JsonObject(mapValues { it.value.novaRpc() })
}

@Serializable data class NovaProcessOption(val id: String, val name: String)

@Serializable data class NovaProcessRow(
    val id: String, @SerialName("company_id") val companyId: String, @SerialName("company_name") val companyName: String, val title: String,
    val date: String, val expected: String, val values: Map<String, JsonElement> = emptyMap(), val number: String? = null, val revision: Int? = null,
    val children: List<NovaProcessRow>? = null, @SerialName("child_kind") val childKind: String? = null,
    @SerialName("child_summary") val childSummary: ChildSummary? = null, @SerialName("workplace_name") val workplaceName: String? = null,
    @SerialName("document_id") val documentId: String? = null, @SerialName("related_kind") val relatedKind: String? = null,
    @SerialName("related_id") val relatedId: String? = null,
) {
    @Serializable data class ChildSummary(val total: Int, val open: Int, val overdue: Int)
}

@Serializable data class NovaProcessPage(val rows: List<NovaProcessRow> = emptyList(), @SerialName("has_more") val hasMore: Boolean = false,
                                         val workplaces: List<NovaProcessOption> = emptyList(), val employees: List<NovaProcessOption> = emptyList(),
                                         val documents: List<NovaProcessOption> = emptyList(), val organizations: List<NovaProcessOption> = emptyList())

@Serializable data class NovaVisitSummary(@SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String,
                                          @SerialName("company_id") val companyId: String? = null, val visits: Int,
                                          @SerialName("recorded_minutes") val recordedMinutes: Int? = null, @SerialName("timed_visits") val timedVisits: Int,
                                          @SerialName("last_visited_on") val lastVisitedOn: String? = null)

class NovaProcessException(val code: String) : Exception(code)

/** Process records boundary (iOS `NovaProcessService`). */
@Singleton
class NovaProcessService @Inject constructor(private val transport: NovaExpertTransport, private val journal: NovaModuleMutationJournal,
                                             private val files: NovaFileLibraryService) {
    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaProcessException("ACCESS_DENIED")
    }

    private suspend fun call(identity: IsgWorkspaceIdentity, function: String, params: JsonObject): JsonElement {
        check(identity)
        val data = try { transport.execute(function, params) } catch (failure: NovaExpertFailure) {
            currentCoroutineContext().ensureActive(); throw NovaProcessException(failure.code)
        }
        check(identity); return data
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaProcessException("UNAVAILABLE") }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull

    suspend fun page(identity: IsgWorkspaceIdentity, kind: String, company: String?, parent: String? = null, query: String = "", offset: Int = 0): NovaProcessPage =
        call(identity, "isg_pilot_process_read_v1", buildJsonObject {
            put("p_kind", kind); put("p_company", text(company)); put("p_id", JsonNull); put("p_parent", text(parent)); put("p_query", query); put("p_offset", offset)
        }).decode(NovaProcessPage.serializer())

    suspend fun record(identity: IsgWorkspaceIdentity, kind: String, company: String, id: String): NovaProcessRow =
        call(identity, "isg_pilot_process_read_v1", buildJsonObject {
            put("p_kind", kind); put("p_company", company); put("p_id", id); put("p_parent", JsonNull); put("p_query", ""); put("p_offset", 0)
        }).decode(NovaProcessRow.serializer())

    /** A summary that does not answer for this owner and company is refused rather than shown. */
    suspend fun visitSummary(identity: IsgWorkspaceIdentity, company: String?): NovaVisitSummary {
        val result = call(identity, "isg_pilot_visit_summary_v1", buildJsonObject {
            put("p_company", text(company)); put("p_from", JsonNull); put("p_to", JsonNull)
        }).decode(NovaVisitSummary.serializer())
        if (result.schemaVersion != 1 || !result.ownerId.equals(identity.userId, true) || !result.companyId.equals(company, true) ||
            result.visits < 0 || result.timedVisits < 0 || result.timedVisits > result.visits) throw NovaProcessException("ACCESS_DENIED")
        return result
    }

    @Serializable private data class AttachmentResult(@SerialName("entry_id") val entryId: String)

    suspend fun attachment(identity: IsgWorkspaceIdentity, kind: String, record: String, field: String): NovaFileEntry {
        val id = call(identity, "isg_pilot_process_attachment_v1", buildJsonObject {
            put("p_kind", kind); put("p_record", record); put("p_field", field)
        }).decode(AttachmentResult.serializer()).entryId
        val entry = files.detail(identity, id)
        check(identity); return entry
    }

    suspend fun contents(identity: IsgWorkspaceIdentity, entry: NovaFileEntry): ByteArray = files.contents(identity, entry)

    suspend fun references(identity: IsgWorkspaceIdentity, kind: String, company: String, id: String? = null, query: String = "", offset: Int = 0): NovaProcessPage =
        call(identity, "isg_pilot_process_references_v1", buildJsonObject {
            put("p_kind", kind); put("p_company", company); put("p_id", text(id)); put("p_query", query); put("p_offset", offset)
        }).decode(NovaProcessPage.serializer())

    @Serializable private data class Deleted(val deleted: Boolean)

    /** Saves, deletes or exports; a row for another company, or with no version, is refused. */
    suspend fun mutate(identity: IsgWorkspaceIdentity, company: String, action: String, payload: JsonObject): NovaProcessRow? {
        check(identity)
        return try {
            journal.run("isg_pilot_process_mutate_v1", identity, company, action, payload) { data ->
                if (action == "delete") {
                    if (!data.decode(Deleted.serializer()).deleted) throw NovaProcessException("ACCESS_DENIED")
                    null
                } else {
                    val row = data.decode(NovaProcessRow.serializer())
                    if (!row.companyId.equals(company, true) || row.expected.isEmpty()) throw NovaProcessException("ACCESS_DENIED")
                    row
                }
            }
        } catch (failure: NovaExpertFailure) {
            currentCoroutineContext().ensureActive(); throw NovaProcessException(failure.code)
        }
    }

    companion object {
        fun message(error: Throwable): String = when ((error as? NovaProcessException)?.code) {
            null, "UNAVAILABLE" -> "İşlem tamamlanamadı. Bağlantıyı kontrol edip yeniden deneyin."
            "VERSION_CONFLICT" -> "Kayıt başka bir işlemde değişti. Kapatıp güncel kaydı yeniden açın."
            "DEPENDENT_RECORDS" -> "Önce bu kayda bağlı alt kayıtları kaldırın."
            "PLAN_YEAR_MISMATCH" -> "Faaliyet tarihi plan yılı içinde olmalı."
            "FUTURE_DATE" -> "Gerçekleşme tarihi gelecekte olamaz."
            "ACCESS_DENIED" -> "Firma, işyeri ve personel bağlantılarını kontrol edin."
            else -> "Bilgiler kaydedilemedi. Zorunlu alanları, tarihleri ve durum seçimini kontrol edin."
        }
    }
}
