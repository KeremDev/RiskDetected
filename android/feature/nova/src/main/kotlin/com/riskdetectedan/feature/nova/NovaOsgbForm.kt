package com.riskdetectedan.feature.nova

import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.designsystem.isg.*
import java.time.LocalDate

/**
 * A local file chosen inside an OSGB form (iOS `IsgWorkspaceAttachmentDraft`). Uploading waits until the
 * parent record is saved, so a cancelled form never leaves an unrelated archive entry behind.
 */
internal class OsgbAttachment(val title: String, val filename: String, val data: ByteArray) {
    val digest: String get() = java.security.MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
}

internal fun osgbToday(): String = LocalDate.now().toString()
internal fun osgbDay(days: Long = 0, from: String = osgbToday()): String =
    runCatching { LocalDate.parse(from).plusDays(days).toString() }.getOrDefault(from)

/** The inline attachment picker of OSGB create and action flows (iOS `IsgWorkspaceInlineAttachmentField`). */
@Composable
internal fun OsgbAttachmentField(title: String, attachment: OsgbAttachment?, onChange: (OsgbAttachment?) -> Unit,
                                 help: String = "PDF, Office, CSV veya görsel · en fazla 50 MB", identifier: String = "osgb.attachment") {
    val context = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching {
            val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "belge"
            val extension = name.substringAfterLast('.', "").lowercase()
            if (extension !in IsgWorkspaceRepository.FILE_TYPES) error("type")
            val data = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("empty")
            if (data.size !in 1..52_428_800) error("size")
            OsgbAttachment(name.substringBeforeLast('.').trim().ifEmpty { name }, name, data)
        }.onSuccess { onChange(it); error = null }.onFailure { onChange(null); error = "Dosya okunamadı veya 50 MB sınırını aşıyor." }
    }
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp)
            .novaRowPress { picker.launch(IsgWorkspaceRepository.FILE_TYPES.values.distinct().toTypedArray()) }.padding(12.dp).testTag(identifier),
            horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(if (attachment == null) "doc.badge.plus" else "doc.fill", 19.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaText(attachment?.filename ?: title, style = NovaTypeToken.bodyStrong)
                NovaText(if (attachment == null) help else "Dosya kayıtla birlikte yüklenecek.", style = NovaTypeToken.metaQuiet)
            }
            NovaIcon(if (attachment == null) "chevron.right" else "arrow.triangle.2.circlepath", 12.dp)
        }
        if (attachment != null) Row(Modifier.heightIn(min = 36.dp).novaRowPress { onChange(null) }, horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("xmark.circle", 14.dp, tint = NovaColorToken.statusDangerInk.color())
            NovaText("Seçimi kaldır", style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color())
        }
        error?.let { NovaHelpHint(it) }
    }
}

/**
 * A chooser over fixed raw values (iOS `NovaChoiceField`), titled through the workspace display text unless [titles]
 * says otherwise. Nothing reads as chosen until a value is picked: the field shows [placeholder] (or its label) and
 * opens a bottom sheet of the values, with search for long lists.
 */
@Composable
internal fun OsgbPicker(label: String, values: List<String>, selected: String?, identifier: String, titles: Map<String, String> = emptyMap(),
                        placeholder: String? = null, onPick: (String) -> Unit) {
    NovaChoiceField(label, placeholder ?: label, osgbPickerSymbol(identifier),
        values.map { NovaChoiceOption(it, titles[it] ?: IsgWorkspaceDisplayText.value(it)) },
        selected?.takeIf { it in values }, { value -> value?.let(onPick) }, identifier, boxed = true)
}

/** The field icon, read from what the picker's identifier names. */
private fun osgbPickerSymbol(identifier: String): String = when {
    "workplace" in identifier -> "building.2"
    "employee" in identifier -> "person"
    "department" in identifier -> "square.grid.2x2"
    "plan" in identifier -> "flame"
    "template" in identifier || ".item" in identifier -> "checklist"
    "category" in identifier -> "folder"
    "severity" in identifier -> "exclamationmark.triangle"
    "role" in identifier || "team" in identifier -> "person.2"
    "training" in identifier -> "graduationcap"
    "equipment" in identifier -> "wrench.and.screwdriver"
    "source" in identifier -> "clock"
    "relation" in identifier -> "link"
    else -> "list.bullet"
}

/** A labelled integer stepper (iOS `Stepper`). */
@Composable
internal fun OsgbStepper(label: String, value: Int, range: IntRange, identifier: String, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp).padding(horizontal = 12.dp)
        .testTag(identifier), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText(label, Modifier.weight(1f), NovaTypeToken.body)
        listOf("minus" to value - 1, "plus" to value + 1).forEach { (symbol, next) ->
            val enabled = next in range
            Box(Modifier.size(36.dp).clip(CircleShape).novaRowPress(enabled = enabled) { onChange(next) }
                .semantics { contentDescription = if (symbol == "plus") "Artır" else "Azalt" }.testTag("$identifier.$symbol"),
                contentAlignment = Alignment.Center) {
                NovaIcon(symbol, 15.dp, tint = if (enabled) NovaColorToken.text.color() else NovaColorToken.textPlaceholder.color())
            }
        }
    }
}

/** A multi-select list of company employees. */
@Composable
internal fun OsgbEmployeePicker(employees: List<Pair<String, String>>, selected: Set<String>, loading: Boolean, onToggle: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText("Katılımcılar", style = NovaTypeToken.bodyStrong)
        if (loading) NovaSpinner(NovaColorToken.text.color(), size = 18.dp)
        if (!loading && employees.isEmpty()) NovaText("Bu firmada kayıtlı personel yok.", style = NovaTypeToken.metaQuiet)
        employees.forEach { (id, name) ->
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress { onToggle(id) }.testTag("osgb.employee.$id"),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon(if (id in selected) "checkmark.circle.fill" else "circle", 18.dp)
                NovaText(name, Modifier.weight(1f))
            }
        }
    }
}

/** Uploads a form's attachment and links it to its parent record, both replay-safe (iOS `uploadFile` + `attachFile`). */
internal suspend fun osgbUploadAttachment(repository: IsgWorkspaceRepository, context: IsgWorkspaceContext, companyId: String,
                                          attempt: IsgWorkspaceMutationAttempt, namespace: String, attachment: OsgbAttachment,
                                          category: String): Pair<String, String> =
    repository.uploadFile(context, attempt.id("$namespace.file.upload", attachment.filename, attachment.digest), companyId,
        attachment.title, attachment.filename, category, attachment.data)

internal suspend fun osgbAttachFile(repository: IsgWorkspaceRepository, context: IsgWorkspaceContext, companyId: String,
                                    attempt: IsgWorkspaceMutationAttempt, namespace: String, entryId: String, parentKind: String,
                                    parentId: String, fieldName: String) {
    repository.mutateDomain(context, attempt.id("$namespace.file.attach", entryId, parentId, parentKind), companyId, IsgWorkspaceDomain.FILES,
        kotlinx.serialization.json.buildJsonObject {
            put("action", kotlinx.serialization.json.JsonPrimitive("attach")); put("entry_id", kotlinx.serialization.json.JsonPrimitive(entryId))
            put("parent_kind", kotlinx.serialization.json.JsonPrimitive(parentKind)); put("parent_id", kotlinx.serialization.json.JsonPrimitive(parentId))
            put("field_name", kotlinx.serialization.json.JsonPrimitive(fieldName))
        })
}
