package com.riskdetectedan.feature.nova

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.io.File
import java.time.LocalDate

/** One record command (iOS `IsgWorkspaceDomainAction`). */
internal enum class OsgbActionKind {
    trainingComplete, trainingCancel, riskEditDraft, riskFinalize, riskCancelDraft, nonconformityTransition, nonconformityAddAction,
    nonconformityVerify, checklistAnswer, checklistSubmit, checklistCancel, drillPerform, drillCancel, appointmentEnd, ppeReturn,
    equipmentInspect, equipmentEdit, equipmentRule, equipmentArchive, katipArchive, annualAddItem, annualClose, boardHold,
    boardAddDecision, boardCancel, permitArchive, visitAddObservation
}

internal data class OsgbAction(val kind: OsgbActionKind, val state: String? = null) {
    val id: String get() = if (kind == OsgbActionKind.nonconformityTransition) "finding.transition.$state" else kind.name
    val title: String get() = when (kind) {
        OsgbActionKind.trainingComplete -> "Eğitimi tamamla"; OsgbActionKind.trainingCancel -> "Eğitimi iptal et"
        OsgbActionKind.riskEditDraft -> "Taslağı düzenle"; OsgbActionKind.riskFinalize -> "Risk analizini kesinleştir"
        OsgbActionKind.riskCancelDraft -> "Taslağı iptal et"
        OsgbActionKind.nonconformityTransition -> mapOf("open" to "Kaydı aç", "assigned" to "Sorumlu ata", "in_progress" to "İşleme al",
            "pending_verification" to "Doğrulamaya gönder", "closed" to "Kaydı kapat", "reopened" to "Yeniden aç",
            "cancelled" to "Kaydı iptal et")[state] ?: "Durumu güncelle"
        OsgbActionKind.nonconformityAddAction -> "Düzeltici faaliyet ekle"; OsgbActionKind.nonconformityVerify -> "Doğrulama kaydet"
        OsgbActionKind.checklistAnswer -> "Kontrol maddesini yanıtla"; OsgbActionKind.checklistSubmit -> "Kontrol listesini gönder"
        OsgbActionKind.checklistCancel -> "Kontrol listesini iptal et"; OsgbActionKind.drillPerform -> "Tatbikatı tamamla"
        OsgbActionKind.drillCancel -> "Tatbikatı iptal et"; OsgbActionKind.appointmentEnd -> "Atamayı sonlandır"
        OsgbActionKind.ppeReturn -> "KKD iadesi kaydet"; OsgbActionKind.equipmentInspect -> "Periyodik kontrol ekle"
        OsgbActionKind.equipmentEdit -> "Ekipmanı düzenle"; OsgbActionKind.equipmentRule -> "Kontrol süresini düzenle"
        OsgbActionKind.equipmentArchive -> "Ekipmanı arşivle"; OsgbActionKind.katipArchive -> "Sözleşmeyi arşivle"
        OsgbActionKind.annualAddItem -> "Plan faaliyeti ekle"; OsgbActionKind.annualClose -> "Yıllık planı kapat"
        OsgbActionKind.boardHold -> "Toplantıyı gerçekleştir"; OsgbActionKind.boardAddDecision -> "Karar ekle"
        OsgbActionKind.boardCancel -> "Toplantıyı iptal et"; OsgbActionKind.permitArchive -> "İzin formunu arşivle"
        OsgbActionKind.visitAddObservation -> "Ziyaret gözlemi ekle"
    }
    val symbol: String get() = when (kind) {
        OsgbActionKind.trainingComplete, OsgbActionKind.checklistSubmit, OsgbActionKind.drillPerform, OsgbActionKind.boardHold -> "checkmark.circle"
        OsgbActionKind.checklistAnswer -> "checklist"
        OsgbActionKind.riskFinalize, OsgbActionKind.nonconformityVerify -> "checkmark.seal"
        OsgbActionKind.riskEditDraft, OsgbActionKind.equipmentEdit -> "pencil"
        OsgbActionKind.riskCancelDraft -> "xmark.circle"
        OsgbActionKind.nonconformityAddAction, OsgbActionKind.annualAddItem, OsgbActionKind.boardAddDecision, OsgbActionKind.visitAddObservation -> "plus"
        OsgbActionKind.appointmentEnd -> "calendar.badge.minus"
        OsgbActionKind.ppeReturn -> "arrow.uturn.backward"
        OsgbActionKind.equipmentInspect -> "calendar.badge.checkmark"
        OsgbActionKind.equipmentRule -> "hourglass"
        OsgbActionKind.nonconformityTransition -> "arrow.triangle.2.circlepath"
        else -> "archivebox"
    }
    val isPrimary: Boolean get() = kind in setOf(OsgbActionKind.trainingComplete, OsgbActionKind.riskFinalize, OsgbActionKind.checklistSubmit,
        OsgbActionKind.drillPerform, OsgbActionKind.equipmentInspect, OsgbActionKind.boardHold, OsgbActionKind.nonconformityVerify)
    val acceptsAttachment: Boolean get() = kind in setOf(OsgbActionKind.trainingComplete, OsgbActionKind.riskFinalize,
        OsgbActionKind.nonconformityAddAction, OsgbActionKind.nonconformityVerify, OsgbActionKind.checklistAnswer, OsgbActionKind.drillPerform,
        OsgbActionKind.ppeReturn, OsgbActionKind.equipmentInspect, OsgbActionKind.annualAddItem, OsgbActionKind.boardHold,
        OsgbActionKind.boardAddDecision, OsgbActionKind.visitAddObservation)
}

private fun IsgWorkspaceRecord.remainingPpe() = maxOf(0, (fact("quantity")?.toIntOrNull() ?: 0) - (fact("returned_quantity")?.toIntOrNull() ?: 0))

/** The commands a record's current state allows (iOS `availableActions`). */
internal fun osgbAvailableActions(domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord): List<OsgbAction> {
    val state = row.status.orEmpty()
    fun t(value: String) = OsgbAction(OsgbActionKind.nonconformityTransition, value)
    return when {
        domain == IsgWorkspaceDomain.TRAINING && state == "planned" -> listOf(OsgbAction(OsgbActionKind.trainingComplete), OsgbAction(OsgbActionKind.trainingCancel))
        domain == IsgWorkspaceDomain.RISK && state == "draft" -> listOf(OsgbAction(OsgbActionKind.riskEditDraft), OsgbAction(OsgbActionKind.riskFinalize),
            OsgbAction(OsgbActionKind.riskCancelDraft))
        domain == IsgWorkspaceDomain.NONCONFORMITY -> {
            val values = when (state) {
                "draft" -> listOf(t("open"), t("cancelled"))
                "open" -> listOf(t("assigned"), t("cancelled"))
                "assigned" -> listOf(t("in_progress"), t("open"), t("cancelled"))
                "in_progress" -> listOf(t("pending_verification"), t("assigned"), t("cancelled"))
                "pending_verification" -> when (row.fact("verification_outcome")) {
                    "accepted" -> listOf(t("closed"), t("in_progress"))
                    "rejected" -> listOf(t("in_progress"))
                    else -> listOf(OsgbAction(OsgbActionKind.nonconformityVerify), t("in_progress"))
                }
                "closed" -> listOf(t("reopened"))
                "reopened" -> listOf(t("assigned"), t("in_progress"), t("cancelled"))
                else -> emptyList()
            }
            if (state !in setOf("closed", "cancelled")) values + OsgbAction(OsgbActionKind.nonconformityAddAction) else values
        }
        domain == IsgWorkspaceDomain.CHECKLIST && state == "open" -> buildList {
            if (row.checklistItems.isNotEmpty()) add(OsgbAction(OsgbActionKind.checklistAnswer))
            if (row.checklistItems.isNotEmpty() && row.checklistItems.all { it.result != null }) add(OsgbAction(OsgbActionKind.checklistSubmit))
            add(OsgbAction(OsgbActionKind.checklistCancel))
        }
        domain == IsgWorkspaceDomain.DRILL && state == "planned" -> listOf(OsgbAction(OsgbActionKind.drillPerform), OsgbAction(OsgbActionKind.drillCancel))
        domain == IsgWorkspaceDomain.APPOINTMENT -> if (row.fact("ends_before")?.let { it <= osgbToday() } == true) emptyList()
            else listOf(OsgbAction(OsgbActionKind.appointmentEnd))
        domain == IsgWorkspaceDomain.PPE -> if (row.remainingPpe() > 0) listOf(OsgbAction(OsgbActionKind.ppeReturn)) else emptyList()
        domain == IsgWorkspaceDomain.EQUIPMENT && state != "archived" -> listOf(OsgbAction(OsgbActionKind.equipmentInspect),
            OsgbAction(OsgbActionKind.equipmentEdit), OsgbAction(OsgbActionKind.equipmentRule), OsgbAction(OsgbActionKind.equipmentArchive))
        domain == IsgWorkspaceDomain.KATIP && state != "archived" -> listOf(OsgbAction(OsgbActionKind.katipArchive))
        domain == IsgWorkspaceDomain.ANNUAL_PLAN && state == "active" -> listOf(OsgbAction(OsgbActionKind.annualAddItem), OsgbAction(OsgbActionKind.annualClose))
        domain == IsgWorkspaceDomain.BOARD && state == "planned" -> listOf(OsgbAction(OsgbActionKind.boardHold), OsgbAction(OsgbActionKind.boardCancel))
        domain == IsgWorkspaceDomain.BOARD && state == "held" -> listOf(OsgbAction(OsgbActionKind.boardAddDecision))
        domain == IsgWorkspaceDomain.WORK_PERMIT && state != "archived" -> listOf(OsgbAction(OsgbActionKind.permitArchive))
        domain == IsgWorkspaceDomain.VISIT -> listOf(OsgbAction(OsgbActionKind.visitAddObservation))
        else -> emptyList()
    }
}

/**
 * The operable part of a record's detail (iOS `IsgWorkspaceDomainDetail`): board decisions to settle, the file
 * to open or archive, and the record commands. [onChanged] closes the detail and reloads the list.
 */
@Composable
internal fun NovaOsgbRecordActions(context: IsgWorkspaceContext, repository: IsgWorkspaceRepository, companyId: String,
                                   domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord, workplaces: Map<String, String>,
                                   companyHazardClass: String, onChanged: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val android = LocalContext.current
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<OsgbAction?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    val canOperate = context.canOperate
    val open = selected
    NovaPopup(open != null, { selected = null }, identifier = "osgb.action.editor") {
        if (open != null) key(open) {
            NovaOsgbActionEditor(context, repository, companyId, domain, row, open, workplaces, companyHazardClass) { selected = null; onChanged() }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (domain == IsgWorkspaceDomain.BOARD && row.boardDecisions.isNotEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NovaText("Kararlar ve takip", style = NovaTypeToken.bodyStrong)
                val decisions = row.boardDecisions.sortedBy { it.number }
                decisions.forEachIndexed { index, decision ->
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NovaText("${decision.number}. ${decision.text}", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                            NovaStatusPill(IsgWorkspaceDisplayText.value(decision.state), when (decision.state) {
                                "done" -> NovaStatus.Success; "cancelled" -> NovaStatus.Neutral; else -> NovaStatus.Warning })
                        }
                        decision.responsibleContact?.takeIf { it.isNotEmpty() }?.let { NovaText("Sorumlu: $it", style = NovaTypeToken.metaQuiet) }
                        decision.dueOn?.let { NovaText("Termin: $it", style = NovaTypeToken.metaQuiet) }
                        if (canOperate && decision.state == "open") Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf("done" to ("Tamamla" to "checkmark"), "cancelled" to ("İptal" to "xmark")).forEach { (state, label) ->
                                NovaCompactActionButton(label.first, label.second, Modifier.weight(1f), enabled = !busy) {
                                    val command = buildJsonObject {
                                        put("kind", "board_decision"); put("action", "settle"); put("id", decision.id)
                                        put("expected_version", decision.version); put("state", state)
                                    }
                                    busy = true; error = null
                                    coroutines.launch {
                                        try {
                                            repository.mutateDomain(context, attempt.id("board.decision.settle", command.toString()), companyId,
                                                IsgWorkspaceDomain.BOARD, command)
                                            celebrate("Kurul kararı kaydedildi.")
                                            onChanged()
                                        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                                            error = "Karar durumu güncellenemedi. Kaydı yenileyip yeniden deneyin."
                                        }
                                        busy = false
                                    }
                                }
                            }
                        }
                    }
                    if (index < decisions.lastIndex) NovaDivider()
                }
            }
        }
        if (domain == IsgWorkspaceDomain.FILES) {
            NovaCompactActionButton(if (busy) "Dosya hazırlanıyor…" else "Dosyayı aç", "arrow.down.doc", Modifier.width(IntrinsicSize.Max),
                prominent = true, enabled = !busy && row.assetId != null, identifier = "osgb.file.open") {
                val asset = row.assetId ?: return@NovaCompactActionButton
                busy = true; error = null
                coroutines.launch {
                    try {
                        val bytes = repository.downloadAsset(context, asset)
                        val name = File(row.originalFilename ?: "belge").name.ifEmpty { "belge" }
                        val file = withContext(Dispatchers.IO) {
                            File(android.cacheDir, "workspace-files/${java.util.UUID.randomUUID()}").apply { mkdirs() }
                                .resolve(name).apply { writeBytes(bytes) }
                        }
                        val uri = FileProvider.getUriForFile(android, "${android.packageName}.fileprovider", file)
                        val type = IsgWorkspaceRepository.FILE_TYPES[name.substringAfterLast('.', "").lowercase()] ?: "application/octet-stream"
                        android.startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), name))
                    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                        error = "Dosya açılamadı. Yetkinizi ve bağlantınızı kontrol edip yeniden deneyin."
                    }
                    busy = false
                }
            }
            if (canOperate) NovaCompactActionButton("Arşivle", "archivebox", Modifier.width(IntrinsicSize.Max), enabled = !busy) {
                busy = true; error = null
                coroutines.launch {
                    try {
                        repository.mutateDomain(context, attempt.id("files.archive", row.id, (row.version ?: 0).toString()), companyId,
                            IsgWorkspaceDomain.FILES, buildJsonObject {
                                put("action", "archive"); put("entry_id", row.id); put("expected_version", row.version ?: 0)
                            })
                        onChanged()
                    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                        error = "Dosya arşivlenemedi. Sayfayı yenileyip yeniden deneyin."
                    }
                    busy = false
                }
            }
        }
        val actions = if (canOperate) osgbAvailableActions(domain, row) else emptyList()
        if (actions.isNotEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaText("Kayıt işlemleri", style = NovaTypeToken.bodyStrong)
                actions.forEach { action ->
                    NovaCompactActionButton(action.title, action.symbol, prominent = action.isPrimary, enabled = !busy,
                        identifier = "osgb.action.${action.id}") { selected = action }
                }
            }
        }
        error?.let { NovaHelpHint(it) }
    }
}

/** One record command's form (iOS `IsgWorkspaceDomainActionEditor`). */
@Composable
private fun NovaOsgbActionEditor(context: IsgWorkspaceContext, repository: IsgWorkspaceRepository, companyId: String,
                                 domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord, action: OsgbAction, workplaces: Map<String, String>,
                                 companyHazardClass: String, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val kind = action.kind
    val riskDraft = row.riskVersions.firstOrNull { it.state == "draft" }
    val periodMonths = maxOf(1, row.fact("period_months")?.toIntOrNull() ?: 12)
    val suggestedRiskPeriod = when (companyHazardClass.lowercase()) {
        "high", "very_dangerous", "cok_tehlikeli", "çok tehlikeli" -> 2; "medium", "dangerous", "tehlikeli" -> 4; else -> 6
    }
    val checklistMinimum = row.fact("started_on") ?: osgbToday()
    val appointmentMinimum = row.fact("starts_on")?.let { osgbDay(1, it) } ?: osgbToday()
    val planYear = row.fact("plan_year")?.toIntOrNull() ?: LocalDate.now().year
    val remainingPpe = row.remainingPpe()
    var note by remember { mutableStateOf("") }
    var contact by remember { mutableStateOf("") }
    var option by remember { mutableStateOf(when (kind) { OsgbActionKind.equipmentInspect -> "pass"; OsgbActionKind.ppeReturn -> "reusable"; else -> "accepted" }) }
    var itemCode by remember { mutableStateOf("") }
    var severity by remember { mutableStateOf("medium") }
    var createFinding by remember { mutableStateOf(false) }
    var number by remember { mutableIntStateOf(1) }
    var date by remember { mutableStateOf(osgbToday()) }
    var secondDate by remember { mutableStateOf(osgbDay(1)) }
    var employees by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var selectedEmployees by remember { mutableStateOf<Set<String>>(emptySet()) }
    var equipmentOpen by remember { mutableStateOf<String?>("control") }
    var hasNextDue by remember { mutableStateOf(true) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var attachmentOpen by remember { mutableStateOf(false) }
    var externalRef by remember { mutableStateOf("") }
    var katipDeclared by remember { mutableStateOf(false) }
    var katipNote by remember { mutableStateOf("") }
    var workplaceId by remember { mutableStateOf<String?>(null) }
    var serialTag by remember { mutableStateOf("") }
    var locationNote by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    fun dueFrom(day: String) = runCatching { LocalDate.parse(day).plusMonths(periodMonths.toLong()).toString() }.getOrDefault(day)
    fun selectItem(code: String) {
        val item = row.checklistItems.firstOrNull { it.code == code }
        itemCode = code
        val current = item?.result ?: "conform"
        option = if (item?.allowsNotApplicable == false && current == "not_applicable") "conform" else current
        note = item?.note.orEmpty(); createFinding = false
    }
    LaunchedEffect(action) {
        when (kind) {
            OsgbActionKind.riskFinalize -> number = row.fact("period_years")?.toIntOrNull() ?: suggestedRiskPeriod
            OsgbActionKind.riskEditDraft -> riskDraft?.let { draft ->
                date = if (draft.kind == "full") draft.assessmentOn else draft.revisionOn ?: draft.assessmentOn
                contact = draft.scopeSummary.orEmpty(); note = draft.reason.orEmpty()
            }
            OsgbActionKind.equipmentInspect -> secondDate = dueFrom(date)
            OsgbActionKind.equipmentEdit -> {
                workplaceId = row.fact("workplace_id")?.lowercase(); serialTag = row.fact("serial_tag") ?: row.subtitle.orEmpty()
                locationNote = row.fact("location_note").orEmpty(); date = row.fact("acquired_on") ?: osgbToday()
            }
            OsgbActionKind.equipmentRule -> {
                number = periodMonths
                option = row.fact("period_source")?.takeIf { it in setOf("manufacturer", "rule_version", "unapproved_fixture") } ?: "manufacturer"
                note = row.fact("period_exception_note").orEmpty()
            }
            OsgbActionKind.checklistAnswer -> row.checklistItems.firstOrNull()?.let {
                selectItem(it.code); if (secondDate < checklistMinimum) secondDate = checklistMinimum
            }
            OsgbActionKind.appointmentEnd -> if (secondDate < appointmentMinimum) secondDate = appointmentMinimum
            OsgbActionKind.annualAddItem -> if (!date.startsWith("$planYear-")) date = "$planYear-01-01"
            else -> Unit
        }
        if (kind in setOf(OsgbActionKind.drillPerform, OsgbActionKind.boardHold, OsgbActionKind.trainingComplete)) {
            loading = true
            try {
                employees = repository.directory(context, companyId, "employees")
                if (kind == OsgbActionKind.trainingComplete) selectedEmployees = row.trainingParticipants.filter { it.attended }.map { it.id.lowercase() }.toSet()
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "Personel listesi yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin."
            }
            loading = false
        }
    }
    val selectedItem = row.checklistItems.firstOrNull { it.code == itemCode }
    val today = osgbToday()
    val controlComplete = option == "fail" || !hasNextDue || secondDate > date
    val canSubmit = when (kind) {
        OsgbActionKind.trainingComplete -> selectedEmployees.isNotEmpty() && row.trainingParticipants.isNotEmpty()
        OsgbActionKind.riskEditDraft -> riskDraft != null && date <= today && (riskDraft.kind != "partial" || contact.isNotBlank()) &&
            (riskDraft.kind !in setOf("partial", "metadata") || note.trim().length >= 10)
        OsgbActionKind.riskCancelDraft -> note.trim().length >= 5
        OsgbActionKind.nonconformityTransition -> when (action.state) {
            "assigned" -> contact.isNotBlank()
            "cancelled", "open", "in_progress", "reopened" -> note.trim().length >= 5
            else -> true
        }
        OsgbActionKind.nonconformityAddAction, OsgbActionKind.annualAddItem, OsgbActionKind.boardAddDecision, OsgbActionKind.visitAddObservation -> note.isNotBlank()
        OsgbActionKind.drillPerform, OsgbActionKind.boardHold -> selectedEmployees.isNotEmpty()
        OsgbActionKind.drillCancel, OsgbActionKind.boardCancel -> note.isNotBlank()
        OsgbActionKind.ppeReturn -> remainingPpe > 0 && number <= remainingPpe
        OsgbActionKind.checklistAnswer -> itemCode.isNotEmpty()
        OsgbActionKind.equipmentInspect -> row.version != null && controlComplete && contact.isNotBlank()
        OsgbActionKind.equipmentEdit -> row.version != null && (workplaces.isEmpty() || workplaceId != null) && serialTag.isNotBlank() && date <= today
        OsgbActionKind.equipmentRule -> !row.fact("equipment_type").isNullOrEmpty() && number in 1..240 &&
            (option != "unapproved_fixture" || note.trim().length >= 10)
        else -> row.version != null
    }
    fun optional(value: String) = value.trim().takeIf { it.isNotEmpty() }?.let(::JsonPrimitive) ?: JsonNull
    fun payload(assetId: String?): JsonObject? {
        val version = row.version ?: return null
        fun merged(block: JsonObjectBuilder.() -> Unit) = buildJsonObject { put("id", row.id); put("expected_version", version); block() }
        val current = row.fact("current_version")?.toIntOrNull()
        return when (kind) {
            OsgbActionKind.trainingComplete -> merged {
                put("action", "complete")
                put("participants", JsonArray(row.trainingParticipants.map { participant ->
                    buildJsonObject { put("id", participant.id); put("attended", participant.id.lowercase() in selectedEmployees) }
                }))
            }
            OsgbActionKind.trainingCancel -> merged { put("action", "cancel") }
            OsgbActionKind.riskEditDraft -> {
                val draft = riskDraft ?: return null
                buildJsonObject {
                    put("action", "edit_draft"); put("assessment_id", row.id); put("expected_current", current ?: return null)
                    put("version", draft.number); put("expected_edit_revision", draft.editRevision)
                    put("assessment_on", if (draft.kind == "full") date else draft.assessmentOn)
                    put("revision_on", if (draft.kind == "full") JsonNull else JsonPrimitive(date))
                    put("scope", buildJsonObject { if (draft.kind == "partial") put("summary", contact.trim()) })
                    put("reason", if (draft.kind in setOf("partial", "metadata")) JsonPrimitive(note.trim()) else JsonNull)
                }
            }
            OsgbActionKind.riskFinalize -> buildJsonObject {
                put("action", "finalize"); put("assessment_id", row.id); put("expected_current", current ?: return null)
                put("version", row.fact("draft_version")?.toIntOrNull() ?: return null)
                put("expected_edit_revision", riskDraft?.editRevision ?: 0)
                put("period_years", if (row.fact("draft_kind") == "full") JsonPrimitive(number) else JsonNull)
            }
            OsgbActionKind.riskCancelDraft -> {
                val draft = riskDraft ?: return null
                buildJsonObject {
                    put("action", "cancel_draft"); put("assessment_id", row.id); put("expected_current", current ?: return null)
                    put("version", draft.number); put("expected_edit_revision", draft.editRevision); put("cancellation_note", note.trim())
                }
            }
            OsgbActionKind.nonconformityTransition -> merged {
                put("action", "transition"); put("to_state", action.state); put("reason", optional(note)); put("assignee_contact", optional(contact))
            }
            OsgbActionKind.nonconformityAddAction -> merged {
                put("action", "add_action"); put("description", note); put("assignee_contact", optional(contact)); put("due_on", secondDate)
            }
            OsgbActionKind.nonconformityVerify -> merged {
                put("action", "verify"); put("verified_on", date); put("outcome", option); put("note", optional(note))
            }
            OsgbActionKind.checklistAnswer -> merged {
                val opens = option == "nonconform" && createFinding && selectedItem?.nonconformityId == null
                put("action", "answer"); put("item_code", itemCode); put("result", option); put("note", optional(note))
                put("create_nonconformity", opens)
                if (opens) { put("severity", severity); put("due_on", secondDate) }
            }
            OsgbActionKind.checklistSubmit -> merged { put("action", "submit") }
            OsgbActionKind.checklistCancel -> merged { put("action", "cancel") }
            OsgbActionKind.drillPerform -> merged {
                put("entity", "drill"); put("action", "perform"); put("performed_on", date)
                put("participants", JsonArray(selectedEmployees.sorted().map(::JsonPrimitive)))
                put("observation", optional(note)); put("improvement", optional(contact))
            }
            OsgbActionKind.drillCancel -> merged { put("entity", "drill"); put("action", "cancel"); put("reason", note) }
            OsgbActionKind.appointmentEnd -> merged { put("entity", "appointment"); put("action", "end"); put("ends_before", secondDate) }
            OsgbActionKind.ppeReturn -> merged {
                put("entity", "ppe"); put("action", "return"); put("quantity", number); put("returned_on", date)
                put("condition", option); put("note", optional(note))
            }
            OsgbActionKind.equipmentInspect -> merged {
                put("action", "record_inspection"); put("performed_on", date); put("result", option)
                put("next_due_on", if (option == "fail" || !hasNextDue) JsonNull else JsonPrimitive(secondDate))
                put("inspector", optional(contact)); put("external_ref", optional(externalRef)); put("note", optional(note))
                put("workspace_asset_id", assetId?.let(::JsonPrimitive) ?: JsonNull); put("katip_declared", katipDeclared)
                put("katip_note", if (katipDeclared) optional(katipNote) else JsonNull)
            }
            OsgbActionKind.equipmentEdit -> {
                merged {
                put("action", "update"); put("workplace_id", workplaceId?.let(::JsonPrimitive) ?: JsonNull); put("serial_tag", serialTag.trim())
                put("acquired_on", date); put("location_note", optional(locationNote))
                }
            }
            OsgbActionKind.equipmentRule -> buildJsonObject {
                put("action", "set_rule"); put("equipment_type", row.fact("equipment_type")?.takeIf { it.isNotEmpty() } ?: return null)
                put("period_months", number); put("period_source", option); put("exception_note", optional(note))
            }
            OsgbActionKind.equipmentArchive -> merged { put("action", "archive") }
            OsgbActionKind.katipArchive -> merged { put("kind", "katip_contract"); put("action", "archive") }
            OsgbActionKind.annualAddItem -> buildJsonObject {
                put("kind", "annual_item"); put("action", "create"); put("plan_id", row.id); put("activity", note)
                put("responsible_contact", optional(contact)); put("planned_on", date)
            }
            OsgbActionKind.annualClose -> merged { put("kind", "annual_plan"); put("action", "close") }
            OsgbActionKind.boardHold -> merged {
                put("kind", "board"); put("action", "hold"); put("held_on", date)
                put("attendance", JsonArray(selectedEmployees.sorted().map(::JsonPrimitive)))
                put("workspace_asset_id", assetId?.let(::JsonPrimitive) ?: JsonNull)
            }
            OsgbActionKind.boardAddDecision -> buildJsonObject {
                put("kind", "board_decision"); put("action", "create"); put("meeting_id", row.id); put("decision_no", number)
                put("decision_text", note); put("responsible_contact", optional(contact)); put("due_on", secondDate)
            }
            OsgbActionKind.boardCancel -> merged { put("kind", "board"); put("action", "cancel"); put("reason", note) }
            OsgbActionKind.permitArchive -> merged { put("kind", "work_permit"); put("action", "archive") }
            OsgbActionKind.visitAddObservation -> buildJsonObject {
                put("kind", "site_observation"); put("action", "create"); put("visit_id", row.id); put("note", note)
                put("workspace_asset_id", assetId?.let(::JsonPrimitive) ?: JsonNull); put("nonconformity_id", JsonNull)
                put("external_ref", optional(contact))
            }
        }
    }
    val category = when (domain) {
        IsgWorkspaceDomain.TRAINING -> "training_material"; IsgWorkspaceDomain.RISK -> "risk_assessment"
        IsgWorkspaceDomain.DRILL -> "emergency_plan"; IsgWorkspaceDomain.PPE -> "handover_form"
        IsgWorkspaceDomain.EQUIPMENT -> "inspection_report"; IsgWorkspaceDomain.BOARD -> "board_document"
        IsgWorkspaceDomain.VISIT -> "visit_evidence"; else -> "other"
    }
    val parentKind = when (domain) {
        IsgWorkspaceDomain.TRAINING -> "training"; IsgWorkspaceDomain.RISK -> "risk_assessment"; IsgWorkspaceDomain.NONCONFORMITY -> "nonconformity"
        IsgWorkspaceDomain.CHECKLIST -> "checklist"; IsgWorkspaceDomain.DRILL -> "drill"; IsgWorkspaceDomain.PPE -> "ppe"
        IsgWorkspaceDomain.EQUIPMENT -> "equipment"; IsgWorkspaceDomain.ANNUAL_PLAN -> "annual_plan"; IsgWorkspaceDomain.BOARD -> "board"
        IsgWorkspaceDomain.VISIT -> "site_visit"; else -> null
    }
    val fieldName = when (kind) {
        OsgbActionKind.equipmentInspect -> "inspection_report"; OsgbActionKind.boardHold -> "minutes"; OsgbActionKind.visitAddObservation -> "evidence"
        OsgbActionKind.ppeReturn -> "return_evidence"; OsgbActionKind.nonconformityVerify -> "verification"; else -> "attachment"
    }
    fun save() {
        if (!canSubmit || saving) return
        saving = true; error = null
        coroutines.launch {
            try {
                val namespace = "domain.action.${action.id}"
                val uploaded = attachment?.takeIf { action.acceptsAttachment }?.let {
                    osgbUploadAttachment(repository, context, companyId, attempt, namespace, it, category)
                }
                val command = payload(uploaded?.second) ?: error("payload")
                repository.mutateDomain(context, attempt.id("domain.action.${domain.name.lowercase()}.${action.id}", command.toString()),
                    companyId, domain, command)
                if (uploaded != null && parentKind != null)
                    osgbAttachFile(repository, context, companyId, attempt, namespace, uploaded.first, parentKind, row.id, fieldName)
                celebrate("${action.title} kaydedildi.")
                onDone()
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "İşlem tamamlanamadı. Kayıt sürümünü ve girdiğiniz bilgileri kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }
    @Composable fun field(title: String, value: String, id: String, onChange: (String) -> Unit) =
        NovaTextField(title, value, onChange, identifier = "osgb.action.$id", multiline = true)
    @Composable fun employeePicker() {
        val rows = if (kind == OsgbActionKind.trainingComplete) {
            val enrolled = row.trainingParticipants.map { it.id.lowercase() }.toSet()
            employees.filter { it.first in enrolled }
        } else employees
        OsgbEmployeePicker(rows, selectedEmployees, loading) { id ->
            selectedEmployees = if (id in selectedEmployees) selectedEmployees - id else selectedEmployees + id
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaText(action.title, style = NovaTypeToken.sectionTitle)
        NovaHelpHint("İşlem ${row.title} kaydına uygulanır ve değişiklik geçmişine yazılır.")
        when (kind) {
            OsgbActionKind.trainingComplete -> {
                NovaHelpHint("Eğitime katılan personeli seçin. Sınavlı müfredatta seçilen herkesin başarılı sınav kaydı bulunmalıdır.")
                employeePicker()
            }
            OsgbActionKind.riskEditDraft -> riskDraft?.let { draft ->
                NovaFormValueRow("Sürüm türü", "square.stack.3d.up") { NovaText(IsgWorkspaceDisplayText.value(draft.kind), style = NovaTypeToken.bodyStrong) }
                NovaDayField(if (draft.kind == "full") "Değerlendirme tarihi" else "Revizyon tarihi", date, { date = minOf(it, today) }, "osgb.action.date")
                if (draft.kind == "partial") field("Kapsam özeti", contact, "scope") { contact = it }
                if (draft.kind in setOf("partial", "metadata")) field("Değişiklik gerekçesi · en az 10 karakter", note, "reason") { note = it }
                NovaHelpHint("Sürüm türü taslak açıldıktan sonra değiştirilemez. Tamamlanmış sürümler düzenlenmez.")
            }
            OsgbActionKind.riskFinalize -> if (row.fact("draft_kind") == "full") {
                OsgbStepper("Geçerlilik süresi: $number yıl", number, 1..20, "osgb.action.period") { number = it }
                NovaHelpHint("${IsgWorkspaceDisplayText.value(companyHazardClass)} tehlike sınıfı için önerilen süre $suggestedRiskPeriod yıldır; gerektiğinde değiştirebilirsiniz.")
            } else NovaHelpHint("Kısmi revizyon ve bilgi düzeltmesi ilk değerlendirmenin geçerlilik tarihini değiştirmez.")
            OsgbActionKind.riskCancelDraft -> {
                field("İptal gerekçesi · en az 5 karakter", note, "reason") { note = it }
                NovaHelpHint("Taslak iptal edilir; yürürlükteki risk değerlendirmesi değişmez.")
            }
            OsgbActionKind.nonconformityTransition -> {
                if (action.state == "assigned") field("Sorumlu / iletişim", contact, "contact") { contact = it }
                if (action.state in setOf("cancelled", "open", "in_progress", "reopened")) field("İşlem gerekçesi", note, "reason") { note = it }
            }
            OsgbActionKind.nonconformityAddAction -> {
                field("Düzeltici faaliyet", note, "note") { note = it }
                field("Sorumlu / iletişim", contact, "contact") { contact = it }
                NovaDayField("Termin", secondDate, { secondDate = it }, "osgb.action.due")
            }
            OsgbActionKind.nonconformityVerify -> {
                OsgbPicker("Sonuç", listOf("accepted", "rejected"), option, "osgb.action.outcome") { option = it }
                NovaDayField("Doğrulama tarihi", date, { date = it }, "osgb.action.date")
                field("Doğrulama notu", note, "note") { note = it }
            }
            OsgbActionKind.checklistAnswer -> {
                OsgbPicker("Kontrol maddesi", row.checklistItems.map { it.code }, itemCode, "osgb.action.item",
                    titles = row.checklistItems.associate { it.code to it.prompt }) { selectItem(it) }
                OsgbPicker("Sonuç", if (selectedItem?.allowsNotApplicable != false) listOf("conform", "nonconform", "not_applicable")
                    else listOf("conform", "nonconform"), option, "osgb.action.result") { option = it }
                if (option == "nonconform") {
                    if (selectedItem?.nonconformityId != null) NovaHelpHint("Bu maddeye bağlı uygunsuzluk kaydı daha önce oluşturuldu.")
                    else NovaCompanyToggleRow("Bu madde için uygunsuzluk kaydı aç", createFinding, !saving) { createFinding = it }
                    if (createFinding && selectedItem?.nonconformityId == null) {
                        OsgbPicker("Önem", listOf("low", "medium", "high", "critical"), severity, "osgb.action.severity") { severity = it }
                        NovaDayField("Düzeltme termini", secondDate, { secondDate = maxOf(it, checklistMinimum) }, "osgb.action.due")
                    }
                }
                field("Madde notu", note, "note") { note = it }
            }
            OsgbActionKind.drillPerform, OsgbActionKind.boardHold -> {
                NovaDayField(if (kind == OsgbActionKind.drillPerform) "Gerçekleşme tarihi" else "Toplantı tarihi", date, { date = it }, "osgb.action.date")
                employeePicker()
                if (kind == OsgbActionKind.drillPerform) {
                    field("Gözlem", note, "note") { note = it }
                    field("İyileştirme", contact, "improvement") { contact = it }
                }
            }
            OsgbActionKind.drillCancel, OsgbActionKind.boardCancel -> field("İptal gerekçesi", note, "reason") { note = it }
            OsgbActionKind.appointmentEnd -> NovaDayField("Bitiş tarihi", secondDate, { secondDate = maxOf(it, appointmentMinimum) }, "osgb.action.end")
            OsgbActionKind.ppeReturn -> {
                OsgbStepper("İade adedi: $number", number, 1..maxOf(1, remainingPpe), "osgb.action.quantity") { number = it }
                NovaDayField("İade tarihi", date, { date = it }, "osgb.action.date")
                OsgbPicker("Durum", listOf("reusable", "worn", "damaged", "lost"), option, "osgb.action.condition") { option = it }
                field("Not", note, "note") { note = it }
            }
            OsgbActionKind.equipmentEdit -> {
                if (workplaces.isNotEmpty()) OsgbPicker("İşyeri", workplaces.entries.sortedBy { it.value }.map { it.key }, workplaceId, "osgb.action.workplace",
                    titles = workplaces, placeholder = "İşyeri seçin") { workplaceId = it }
                field("Seri / kod", serialTag, "serial") { serialTag = it }
                field("Konum (isteğe bağlı)", locationNote, "location") { locationNote = it }
                NovaDayField("Edinme tarihi", date, { date = minOf(it, today) }, "osgb.action.date")
            }
            OsgbActionKind.equipmentRule -> {
                NovaFormValueRow("Ekipman türü", "shippingbox") { NovaText(row.title, style = NovaTypeToken.bodyStrong) }
                OsgbStepper("Kontrol süresi: $number ay", number, 1..240, "osgb.action.period") { number = it }
                OsgbPicker("Süre kaynağı", listOf("manufacturer", "rule_version", "unapproved_fixture"), option, "osgb.action.source",
                    titles = mapOf("manufacturer" to "Üretici kılavuzu", "rule_version" to "Yayımlanmış kural / standart",
                        "unapproved_fixture" to "Uzman tarafından belirlenen")) { option = it }
                if (option == "unapproved_fixture") field("İstisna ve dayanak notu · en az 10 karakter", note, "exception") { note = it }
                NovaHelpHint("Bu süre aynı firmadaki aynı ekipman türünün sonraki kontrollerinde kullanılır; geçmiş raporların tarihleri değişmez.")
            }
            OsgbActionKind.equipmentInspect -> {
                NovaCompanyAccordion("Kontrol ve sonuç", "calendar.badge.checkmark", equipmentOpen == "control", { equipmentOpen = if (it) "control" else null },
                    state = if (controlComplete) NovaCompletionState.complete else NovaCompletionState.missing,
                    identifier = "workspace.equipment.inspection.control") {
                    NovaDayField("Kontrol tarihi", date, { date = minOf(it, today); if (option != "fail") secondDate = dueFrom(date) }, "osgb.action.date")
                    if (hasNextDue && option != "fail") NovaDayField("Sonraki kontrol", secondDate, { secondDate = it }, "osgb.action.next")
                    else NovaFormValueRow("Sonraki kontrol") { NovaText("Tarih yok", style = NovaTypeToken.bodyStrong) }
                    OsgbPicker("Sonuç", listOf("pass", "conditional", "fail"), option, "osgb.action.result") {
                        option = it
                        if (it == "fail") hasNextDue = false else { hasNextDue = true; secondDate = dueFrom(date) }
                    }
                    NovaHelpHint(if (option == "fail") "Olumsuz kontrolde sonraki tarih oluşturulmaz. Düzeltme sonrası yeni kontrol kaydı girin."
                        else "Sonraki tarih $periodMonths aylık süreden hesaplandı; uzman gerekirse değiştirebilir.")
                }
                NovaCompanyAccordion("Kontrol bilgileri", "person.text.rectangle", equipmentOpen == "details", { equipmentOpen = if (it) "details" else null },
                    state = if (contact.isNotBlank()) NovaCompletionState.complete else NovaCompletionState.missing,
                    identifier = "workspace.equipment.inspection.details") {
                    field("Kontrolü yapan", contact, "inspector") { contact = it }
                    field("Rapor no / harici referans", externalRef, "reference") { externalRef = it }
                    NovaCompanyToggleRow("İSG-KATİP ataması yapıldı", katipDeclared, !saving) { katipDeclared = it }
                    if (katipDeclared) field("İSG-KATİP beyan notu", katipNote, "katip") { katipNote = it }
                    field("Kontrol notu", note, "note") { note = it }
                }
                NovaCompanyAccordion("Kontrol raporu", "doc.badge.plus", equipmentOpen == "report", { equipmentOpen = if (it) "report" else null },
                    state = NovaCompletionState.complete, identifier = "workspace.equipment.inspection.report") {
                    OsgbAttachmentField("Kontrol raporunu bu işlemde ekle (isteğe bağlı)", attachment, { attachment = it })
                    NovaHelpHint("Rapor seçilirse kontrol kaydıyla birlikte yüklenir ve ekipman geçmişine bağlanır.")
                }
            }
            OsgbActionKind.annualAddItem -> {
                field("Faaliyet", note, "activity") { note = it }
                field("Sorumlu / iletişim", contact, "contact") { contact = it }
                NovaDayField("Planlanan tarih", date, { value -> date = value.takeIf { it.startsWith("$planYear-") } ?: date }, "osgb.action.date")
            }
            OsgbActionKind.boardAddDecision -> {
                OsgbStepper("Karar no: $number", number, 1..10_000, "osgb.action.number") { number = it }
                field("Karar", note, "decision") { note = it }
                field("Sorumlu / iletişim", contact, "contact") { contact = it }
                NovaDayField("Termin", secondDate, { secondDate = it }, "osgb.action.due")
            }
            OsgbActionKind.visitAddObservation -> {
                field("Gözlem", note, "note") { note = it }
                field("Harici referans", contact, "reference") { contact = it }
            }
            else -> NovaHelpHint("Bu işlem mevcut kayıt sürümü doğrulandıktan sonra uygulanır.")
        }
        if (action.acceptsAttachment && kind != OsgbActionKind.equipmentInspect)
            NovaCompanyAccordion("Dosya ve kanıt", "doc.badge.plus", attachmentOpen, { attachmentOpen = it },
                identifier = "workspace.domain.action.attachment") {
                OsgbAttachmentField("Bu işleme dosya ekle (isteğe bağlı)", attachment, { attachment = it })
            }
        error?.let { NovaHelpHint(it) }
        NovaCompactActionButton(if (saving) "Kaydediliyor…" else action.title, action.symbol, prominent = true,
            enabled = canSubmit && !saving && !loading, identifier = "osgb.action.save") { save() }
    }
}
