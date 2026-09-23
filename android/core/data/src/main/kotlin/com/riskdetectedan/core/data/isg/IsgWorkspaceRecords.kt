package com.riskdetectedan.core.data.isg

import kotlinx.serialization.json.*

/** One row of a workspace domain as the OSGB screens show it (iOS `IsgWorkspaceDomainRecord`). */
data class IsgWorkspaceRecord(
    val id: String, val title: String, val subtitle: String?, val status: String?, val version: Long?,
    val facts: List<Pair<String, String>>, val checklistItems: List<ChecklistItem> = emptyList(),
    val trainingParticipants: List<Participant> = emptyList(), val boardDecisions: List<BoardDecision> = emptyList(),
    val riskVersions: List<RiskVersion> = emptyList(), val equipmentInspections: List<Inspection> = emptyList(),
    val assetId: String? = null, val fileExtension: String? = null, val originalFilename: String? = null,
) {
    data class ChecklistItem(val code: String, val prompt: String, val allowsNotApplicable: Boolean, val result: String?, val note: String?,
                             val nonconformityId: String?)
    data class Participant(val id: String, val name: String, val attended: Boolean)
    data class BoardDecision(val id: String, val number: Int, val text: String, val responsibleContact: String?, val dueOn: String?,
                             val state: String, val version: Long)
    data class RiskVersion(val number: Int, val kind: String, val assessmentOn: String, val revisionOn: String?, val scopeSummary: String?,
                           val reason: String?, val state: String, val validUntil: String?, val periodYears: Int?, val periodSource: String?,
                           val periodNeedsReview: Boolean, val sourceDrift: Boolean, val editRevision: Int, val cancellationNote: String?)
    data class Inspection(val id: String, val performedOn: String, val result: String, val nextDueOn: String?, val periodMonths: Int?,
                          val dueSource: String?, val inspector: String?, val externalRef: String?, val note: String?, val assetId: String?,
                          val version: Long, val katipDeclared: Boolean, val katipNote: String?)

    fun fact(key: String) = facts.firstOrNull { it.first == key }?.second
}

data class IsgWorkspaceMetric(val id: String, val value: Long)

data class IsgWorkspaceSnapshot(val domain: IsgWorkspaceDomain, val rows: List<IsgWorkspaceRecord>, val metrics: List<IsgWorkspaceMetric>)

/** Turns workspace API rows into records, exactly as the iOS adapter does. */
object IsgWorkspaceRecords {
    private val idKeys = listOf("employee_id", "training_id", "assessment_id", "nonconformity_id", "run_id", "plan_id", "drill_id",
        "appointment_id", "handover_id", "equipment_id", "contract_id", "meeting_id", "permit_id", "visit_id", "entry_id", "id")

    private fun invalid(): Nothing = throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")
    private fun JsonElement?.obj() = this as? JsonObject
    private fun JsonElement?.array() = this as? JsonArray
    private fun JsonElement?.text() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonElement?.int() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
    private fun JsonElement?.long() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
    private fun JsonElement?.bool() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
    private fun isUuid(value: String?) = value != null && runCatching { java.util.UUID.fromString(value) }.isSuccess

    /** The iOS `display`: text, numbers, yes/no, or a list's count; nothing for empty values. */
    fun display(value: JsonElement?): String? = when {
        value == null || value is JsonNull -> null
        value is JsonPrimitive && value.isString -> value.content.ifEmpty { null }
        value is JsonPrimitive && value.booleanOrNull != null -> if (value.boolean) "Evet" else "Hayır"
        value is JsonPrimitive -> value.content
        value is JsonArray -> if (value.isEmpty()) null else value.size.toString()
        else -> null
    }

    fun snapshot(domain: IsgWorkspaceDomain, page: JsonObject, metrics: JsonObject?) =
        IsgWorkspaceSnapshot(domain, page["rows"].array().orEmpty().map { record(it.obj() ?: invalid(), domain) }, metrics?.let(::metrics).orEmpty())

    /** Nested counters flattened into dotted keys, at most twelve. */
    fun metrics(root: JsonObject): List<IsgWorkspaceMetric> {
        val ignored = setOf("schema_version", "workspace_id", "company_id", "measured")
        val result = mutableListOf<IsgWorkspaceMetric>()
        fun walk(value: JsonObject, prefix: String) {
            for (key in value.keys.sorted()) {
                if (key in ignored) continue
                val path = if (prefix.isEmpty()) key else "$prefix.$key"
                when (val element = value[key]) {
                    is JsonObject -> walk(element, path)
                    is JsonPrimitive -> if (!element.isString && element.booleanOrNull == null) element.longOrNull?.takeIf { it >= 0 }?.let {
                        result += IsgWorkspaceMetric(path, it)
                    }
                    else -> Unit
                }
            }
        }
        walk(root, "")
        return result.take(12)
    }

    private fun titleKeys(domain: IsgWorkspaceDomain) = when (domain) {
        IsgWorkspaceDomain.PERSONNEL -> listOf("name", "full_name", "code")
        IsgWorkspaceDomain.TRAINING -> listOf("title", "trainer")
        IsgWorkspaceDomain.RISK -> listOf("scope", "assessment_id")
        IsgWorkspaceDomain.NONCONFORMITY -> listOf("title")
        IsgWorkspaceDomain.CHECKLIST -> listOf("template_code")
        IsgWorkspaceDomain.EMERGENCY_PLAN -> listOf("scope")
        IsgWorkspaceDomain.DRILL -> listOf("observation", "planned_on")
        IsgWorkspaceDomain.APPOINTMENT -> listOf("kind", "starts_on")
        IsgWorkspaceDomain.PPE -> listOf("item")
        IsgWorkspaceDomain.EQUIPMENT -> listOf("equipment_type_label", "equipment_type", "serial_tag")
        IsgWorkspaceDomain.KATIP -> listOf("counterparty", "scope")
        IsgWorkspaceDomain.ANNUAL_PLAN -> listOf("plan_year")
        IsgWorkspaceDomain.BOARD -> listOf("planned_on", "applicability")
        IsgWorkspaceDomain.WORK_PERMIT -> listOf("job_description", "template_code")
        IsgWorkspaceDomain.VISIT -> listOf("visited_on", "location_note")
        IsgWorkspaceDomain.FILES -> listOf("title", "original_filename")
    }

    fun record(row: JsonObject, domain: IsgWorkspaceDomain): IsgWorkspaceRecord {
        val id = idKeys.firstNotNullOfOrNull { key -> row[key].text()?.takeIf(::isUuid) } ?: invalid()
        val titles = titleKeys(domain)
        val riskVersions = if (domain == IsgWorkspaceDomain.RISK) row["versions"].array()?.map { it.obj() ?: invalid() } else null
        val riskTitle = riskVersions?.firstOrNull()?.get("scope").obj()?.get("summary").text()?.trim()?.ifEmpty { null }
        val title = riskTitle ?: titles.firstNotNullOfOrNull { display(row[it]) } ?: id
        val status = if (domain == IsgWorkspaceDomain.RISK) when {
            riskVersions?.any { display(it["state"]) == "draft" } == true -> "draft"
            (row["current_version"].int() ?: 0) > 0 -> "final"
            else -> display(riskVersions?.firstOrNull()?.get("state"))
        } else listOf("state", "status").firstNotNullOfOrNull { display(row[it]) }
        val subtitle = listOf("code", "serial_tag", "trainer", "location", "location_note", "expert_contact", "opened_on", "prepared_on",
            "planned_on", "visited_on", "starts_on", "original_filename").firstNotNullOfOrNull { display(row[it]) }
        val hidden = (idKeys + titles + listOf("state", "status", "version", "workspace_id", "company_id", "created_by_user_id", "updated_by_user_id",
            "created_at", "updated_at", "participants", "versions", "items", "asset", "team", "actions", "attendance", "agenda", "decisions")).toSet()
        val facts = row.keys.sorted().mapNotNull { key -> if (key in hidden) null else display(row[key])?.let { key to it } }.toMutableList()
        if (domain == IsgWorkspaceDomain.EQUIPMENT) for (key in listOf("serial_tag", "equipment_type_label", "equipment_type")) {
            val value = display(row[key])
            if (value != null && facts.none { it.first == key }) facts.add(0, key to value)
        }
        if (domain == IsgWorkspaceDomain.EMERGENCY_PLAN) row["team"].array()?.let { team ->
            facts += "team_size" to team.size.toString()
            val names = team.mapNotNull { it.obj()?.get("full_name").text() }
            if (names.isNotEmpty()) facts += "team_members" to names.joinToString(", ")
        }
        if (domain == IsgWorkspaceDomain.BOARD) {
            row["agenda"].array()?.let { agenda ->
                facts += "agenda_count" to agenda.size.toString()
                agenda.firstOrNull().text()?.takeIf { it.isNotEmpty() }?.let { facts += "agenda_summary" to it }
            }
            row["attendance"].array()?.let { facts += "attendance_count" to it.size.toString() }
            row["decisions"].array()?.let { decisions ->
                facts += "decision_count" to decisions.size.toString()
                facts += "open_decision_count" to decisions.count { it.obj()?.get("state").text() == "open" }.toString()
            }
        }
        riskVersions?.firstOrNull { display(it["state"]) == "draft" }?.let { draft ->
            display(draft["version"])?.let { facts += "draft_version" to it }
            display(draft["kind"])?.let { facts += "draft_kind" to it }
        }
        if (domain == IsgWorkspaceDomain.TRAINING) row["curriculum_snapshot"].obj()?.let { snapshot ->
            display(snapshot["title"])?.let { facts += "curriculum_title" to it }
            display(snapshot["revision"])?.let { facts += "curriculum_revision" to it }
            display(snapshot["assessment_required"])?.let { facts += "assessment_required" to it }
        }
        val checklist = if (domain == IsgWorkspaceDomain.CHECKLIST) row["items"].array()?.map { element ->
            val item = element.obj() ?: invalid()
            val result = item["result"].text()
            if (result != null && result !in setOf("conform", "nonconform", "not_applicable")) invalid()
            val finding = item["nonconformity_id"]
            if (finding != null && finding !is JsonNull && !isUuid(finding.text())) invalid()
            IsgWorkspaceRecord.ChecklistItem(item["item_code"].text()?.ifEmpty { null } ?: invalid(), item["prompt"].text()?.ifEmpty { null } ?: invalid(),
                item["allows_not_applicable"].bool() ?: invalid(), result, item["note"].text(), finding.text())
        }.orEmpty() else emptyList()
        if (checklist.size > 500 || checklist.map { it.code }.toSet().size != checklist.size) invalid()
        val participants = if (domain == IsgWorkspaceDomain.TRAINING) row["participants"].array()?.map { element ->
            val value = element.obj() ?: invalid()
            IsgWorkspaceRecord.Participant(value["employee_id"].text()?.takeIf(::isUuid) ?: invalid(), value["name"].text()?.ifEmpty { null } ?: invalid(),
                value["attended"].bool() ?: invalid())
        }.orEmpty() else emptyList()
        if (participants.size > 500 || participants.map { it.id }.toSet().size != participants.size) invalid()
        val decisions = if (domain == IsgWorkspaceDomain.BOARD) row["decisions"].array()?.map { element ->
            val value = element.obj() ?: invalid()
            val state = value["state"].text()?.takeIf { it in setOf("open", "done", "cancelled") } ?: invalid()
            IsgWorkspaceRecord.BoardDecision(value["decision_id"].text()?.takeIf(::isUuid) ?: invalid(), value["decision_no"].int() ?: invalid(),
                value["decision_text"].text()?.ifEmpty { null } ?: invalid(), value["responsible_contact"].text(), value["due_on"].text(), state,
                value["version"].long() ?: invalid())
        }.orEmpty() else emptyList()
        if (decisions.size > 500 || decisions.map { it.id }.toSet().size != decisions.size) invalid()
        val versions = riskVersions?.map { value ->
            val scope = value["scope"]
            val summary = when (scope) {
                null, JsonNull -> null
                is JsonObject -> display(scope["summary"])
                is JsonArray -> scope.mapNotNull { it.text() }.takeIf { it.isNotEmpty() }?.joinToString(", ")
                else -> invalid()
            }
            IsgWorkspaceRecord.RiskVersion(value["version"].int()?.takeIf { it > 0 } ?: invalid(),
                value["kind"].text()?.takeIf { it in setOf("full", "partial", "metadata", "rescan") } ?: invalid(),
                value["assessment_on"].text()?.ifEmpty { null } ?: invalid(), value["revision_on"].text(), summary, value["reason"].text(),
                value["state"].text()?.takeIf { it in setOf("draft", "final", "superseded", "cancelled") } ?: invalid(), value["valid_until"].text(),
                value["period_years"].int(), value["period_source"].text(), value["period_needs_review"].bool() ?: false,
                value["source_drift"].bool() ?: false, value["edit_revision"].int() ?: 0, value["cancellation_note"].text())
        }.orEmpty()
        if (versions.size > 500 || versions.map { it.number }.toSet().size != versions.size) invalid()
        val inspections = if (domain == IsgWorkspaceDomain.EQUIPMENT) row["inspections"].array()?.map { element ->
            val value = element.obj() ?: invalid()
            val asset = value["workspace_asset_id"]
            if (asset != null && asset !is JsonNull && !isUuid(asset.text())) invalid()
            IsgWorkspaceRecord.Inspection(value["inspection_id"].text()?.takeIf(::isUuid) ?: invalid(),
                value["performed_on"].text()?.ifEmpty { null } ?: invalid(),
                value["result"].text()?.takeIf { it in setOf("pass", "conditional", "fail") } ?: invalid(), value["next_due_on"].text(),
                value["period_months"].int(), value["due_source"].text(), value["inspector"].text(), value["external_ref"].text(), value["note"].text(),
                asset.text(), value["version"].long()?.takeIf { it >= 0 } ?: invalid(), value["katip_assignment_declared"].bool() ?: false,
                value["katip_declared_note"].text())
        }.orEmpty() else emptyList()
        if (inspections.size > 500 || inspections.map { it.id }.toSet().size != inspections.size) invalid()
        val asset = row["asset"].obj()
        return IsgWorkspaceRecord(id, title, subtitle, status, row["version"].long(), facts.take(14), checklist, participants, decisions, versions,
            inspections, asset?.get("id").text()?.takeIf(::isUuid), asset?.get("extension").text(), row["original_filename"].text())
    }
}

/** API vocabulary turned into product copy (iOS `IsgWorkspaceDisplayText`); the pilot is Turkish-only. */
object IsgWorkspaceDisplayText {
    fun value(raw: String) = values[raw.lowercase()] ?: humanized(raw)
    fun field(raw: String) = fields[raw.lowercase()] ?: humanized(raw)
    fun metric(raw: String): String {
        metrics[raw.lowercase()]?.let { return it }
        val last = raw.substringAfterLast('.')
        return metrics[last.lowercase()] ?: humanized(last)
    }
    fun event(raw: String) = raw.replace("workspace.", "").split('.').joinToString(" · ") { value(it) }
    fun metricValue(id: String, value: Long): String {
        if (!id.contains("minute")) return value.toString()
        val hours = value / 60.0
        return if (hours == Math.rint(hours)) hours.toLong().toString() else String.format(java.util.Locale.US, "%.1f", hours)
    }
    private fun humanized(raw: String) = raw.replace('_', ' ').replace('.', ' ').split(' ').filter { it.isNotEmpty() }
        .joinToString(" ") { word -> word.replaceFirstChar { it.titlecase(java.util.Locale.forLanguageTag("tr-TR")) } }

    private val values = mapOf(
        "active" to "Aktif", "archived" to "Arşivlendi", "draft" to "Taslak", "planned" to "Planlandı", "completed" to "Tamamlandı",
        "cancelled" to "İptal edildi", "open" to "Açık", "assigned" to "Atandı", "in_progress" to "İşlemde",
        "pending_verification" to "Doğrulama bekliyor", "closed" to "Kapatıldı", "reopened" to "Yeniden açıldı", "published" to "Yayımlandı",
        "retired" to "Kullanımdan kaldırıldı", "verified" to "Doğrulandı", "realised" to "Gerçekleşti", "performed" to "Gerçekleştirildi",
        "done" to "Tamamlandı", "valid" to "Güncel", "overdue" to "Süresi geçti", "due_soon" to "Yaklaşıyor", "expired" to "Süresi doldu",
        "failed" to "Başarısız", "pass" to "Uygun", "conditional" to "Şartlı uygun", "fail" to "Olumsuz", "conform" to "Uygun",
        "nonconform" to "Uygunsuz", "not_applicable" to "Uygulanamaz", "accepted" to "Kabul edildi", "rejected" to "Reddedildi",
        "pending" to "Bekliyor", "low" to "Düşük", "medium" to "Orta", "high" to "Yüksek", "critical" to "Kritik", "face_to_face" to "Yüz yüze",
        "online" to "Çevrim içi", "mixed" to "Karma", "representative" to "Çalışan temsilcisi", "support_staff" to "Destek elemanı",
        "team_member" to "Ekip üyesi", "first_aid" to "İlk yardımcı", "fire_team" to "Yangın ekibi", "coordinator" to "Koordinatör",
        "fire" to "Yangın", "evacuation" to "Tahliye", "full" to "Tam değerlendirme", "partial" to "Kısmi revizyon",
        "metadata" to "Bilgi düzeltmesi", "rescan" to "Yeniden inceleme", "held" to "Gerçekleşti", "piece" to "Adet", "pair" to "Çift",
        "set" to "Takım", "metre" to "Metre", "litre" to "Litre", "mandatory" to "Zorunlu", "voluntary" to "Gönüllü",
        "reusable" to "Tekrar kullanılabilir", "worn" to "Yıpranmış", "damaged" to "Hasarlı", "lost" to "Kayıp", "initial" to "İlk eğitim",
        "periodic_repeat" to "Periyodik tekrar", "onboarding" to "İşe giriş", "task_specific" to "Göreve özel", "other" to "Diğer",
        "internal_training" to "Kurum içi eğitim", "external_training" to "Harici eğitim", "certificate" to "Sertifika", "owner" to "OSGB sahibi",
        "admin" to "OSGB yöneticisi", "expert" to "İSG uzmanı", "primary" to "Birincil uzman", "support" to "Destek uzmanı",
        "current" to "Güncel", "future" to "İleri tarihli", "upcoming" to "Başlayacak", "ended" to "Sona erdi", "untracked" to "Takip tarihi yok",
        "suspended" to "Askıda", "never_inspected" to "Kontrol yok", "period_unknown" to "Süre belirlenmedi", "true" to "Evet", "false" to "Hayır",
        "lifting_equipment" to "Kaldırma ekipmanı", "crane" to "Vinç", "forklift" to "Forklift", "pressure_vessel" to "Basınçlı kap",
        "compressor" to "Kompresör", "boiler" to "Kazan", "lift" to "Asansör", "scaffold" to "İskele", "ladder" to "Merdiven",
        "electrical_installation" to "Elektrik tesisatı", "earthing" to "Topraklama tesisatı", "fire_extinguisher" to "Yangın söndürücü",
        "fire_detection" to "Yangın algılama sistemi", "ventilation" to "Havalandırma tesisatı", "power_tool" to "Elektrikli el aleti",
        "welding_set" to "Kaynak makinesi", "conveyor" to "Konveyör", "press_machine" to "Pres makinesi", "lathe" to "Torna tezgâhı",
        "other_equipment" to "Diğer ekipman", "regulation_default" to "Genel süre", "company_override" to "Firma süresi",
        "expert_override" to "Uzman süresi",
    )
    private val fields = mapOf(
        "code" to "Kod", "name" to "Ad", "full_name" to "Ad soyad", "state" to "Durum", "status" to "Durum", "version" to "Sürüm",
        "current_version" to "Güncel sürüm", "draft_version" to "Taslak sürümü", "draft_kind" to "Taslak türü",
        "assessment_on" to "Değerlendirme tarihi", "revision_on" to "Revizyon tarihi", "scope" to "Kapsam", "severity" to "Önem",
        "opened_on" to "Açılış tarihi", "due_on" to "Termin tarihi", "trainer" to "Eğitmen", "method" to "Eğitim yöntemi",
        "starts_at" to "Başlangıç", "duration_minutes" to "Süre", "valid_until" to "Geçerlilik tarihi", "location" to "Konum", "notes" to "Not",
        "participant_count" to "Katılımcı sayısı", "attended_count" to "Katılan sayısı", "workplace_id" to "İşyeri", "department_id" to "Departman",
        "employee_id" to "Personel", "hired_on" to "İşe giriş tarihi", "ends_before" to "Bitiş tarihi", "prepared_on" to "Hazırlanma tarihi",
        "planned_on" to "Planlanan tarih", "performed_on" to "Gerçekleşme tarihi", "visited_on" to "Ziyaret tarihi", "item" to "Ürün",
        "quantity" to "Adet", "returned_quantity" to "İade edilen", "unit" to "Birim", "handed_on" to "Teslim tarihi",
        "return_condition" to "İade durumu", "signed_copy" to "İmzalı nüsha", "equipment_type" to "Ekipman türü",
        "equipment_type_label" to "Ekipman türü", "serial_tag" to "Seri / kod", "acquired_on" to "Edinme tarihi", "location_note" to "Konum notu",
        "last_performed_on" to "Son kontrol", "next_due_on" to "Sonraki kontrol", "result" to "Sonuç", "inspector" to "Kontrolü yapan",
        "counterparty" to "Sözleşme tarafı", "expert_contact" to "Uzman / iletişim", "declared_monthly_minutes" to "Aylık dakika",
        "declared_note" to "Beyan notu", "plan_year" to "Plan yılı", "applicability" to "Uygulanma durumu", "job_description" to "İş tanımı",
        "work_location" to "Çalışma yeri", "risk_precautions" to "Risk önlemleri", "responsible_contact" to "Sorumlu", "category" to "Belge türü",
        "visibility" to "Görünürlük", "original_filename" to "Dosya adı", "verification_outcome" to "Doğrulama sonucu",
        "verification_note" to "Doğrulama notu", "topic_count" to "Konu sayısı", "total_minutes" to "Toplam süre", "target_group" to "Hedef grup",
        "passing_score" to "Geçme puanı", "certificate_number" to "Belge numarası", "team_size" to "Ekip", "team_members" to "Ekip üyeleri",
        "agenda_count" to "Gündem maddesi", "agenda_summary" to "İlk gündem maddesi", "attendance_count" to "Katılımcı", "decision_count" to "Karar",
        "open_decision_count" to "Açık karar", "base_assessment_on" to "İlk değerlendirme", "period_years" to "Geçerlilik süresi",
        "needs_review" to "İnceleme gerekiyor", "curriculum_title" to "Kayıtlı eğitim", "curriculum_revision" to "Müfredat sürümü",
        "assessment_required" to "Sınav gerekli", "period_months" to "Kontrol süresi", "period_source" to "Süre kaynağı",
        "last_result" to "Son kontrol sonucu", "last_inspector" to "Son kontrolü yapan", "last_external_ref" to "Son rapor no",
        "inspections" to "Kontrol kaydı",
    )
    private val metrics = mapOf(
        "total" to "Toplam", "active" to "Aktif", "archived" to "Arşiv", "planned" to "Planlanan", "completed" to "Tamamlanan", "cancelled" to "İptal",
        "open" to "Açık", "closed" to "Kapatılan", "overdue" to "Süresi geçen", "expired" to "Süresi dolan", "due_soon" to "Yaklaşan",
        "valid" to "Güncel", "failed" to "Olumsuz", "records.total" to "Toplam kayıt", "records.planned" to "Planlanan",
        "records.completed" to "Tamamlanan", "records.cancelled" to "İptal", "completed_minutes" to "Eğitim saati", "trained_people" to "Eğitim alan",
        "person_minutes" to "Adam × saat", "people_without_completed_training" to "Eğitimi eksik", "employee_count" to "Personel",
        "workplace_count" to "İşyeri", "department_count" to "Departman", "positive" to "Olumlu", "negative" to "Olumsuz",
        "untracked" to "Takip tarihi yok", "approaching" to "Yaklaşıyor", "upcoming" to "Başlayacak", "ended" to "Sona eren", "held" to "Gerçekleşen",
        "board_open_decisions" to "Açık karar", "open_decisions" to "Açık karar",
    )
}
