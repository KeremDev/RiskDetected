package com.riskdetectedan.feature.profile

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.notebook.*
import com.riskdetectedan.core.designsystem.isg.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import javax.inject.Inject

object NotebookUIRelease { const val enabled = false }
data class NotebookEditor(val note: String = UUID.randomUUID().toString(), val version: Long = 0, val title: String = "", val body: String = "",
                          val pending: NotebookPending? = null, val serverText: String? = null,
                          val originalTitle: String = title, val originalBody: String = body)
data class NotebookScreenState(val identity: NotebookIdentity? = null, val notes: List<NotebookRecord> = emptyList(),
    val drafts: List<NotebookPending> = emptyList(), val busy: Boolean = false, val message: String? = null, val editor: NotebookEditor? = null,
    val organization: NotebookOrganizationEditor? = null, val reminders: List<NotebookReminder> = emptyList(),
    val reminderEditor: NotebookReminderEditor? = null)
data class NotebookOrganizationEditor(val note: String, val version: Long, val items: List<NotebookItem>, val tags: String,
    val pending: String? = null, val serverText: String? = null)
/** A new reminder, optionally tied to one note; it starts an hour from now. */
data class NotebookReminderEditor(val title: String = "", val recurrence: String = "once", val note: String? = null,
                                  val dueAt: Instant = Instant.now().plus(1, ChronoUnit.HOURS).truncatedTo(ChronoUnit.MINUTES))

@HiltViewModel
class NotebookViewModel @Inject constructor(private val repository: NotebookRepository) : ViewModel() {
    private val mutable = MutableStateFlow(NotebookScreenState())
    val state = mutable.asStateFlow()
    init { viewModelScope.launch { repository.identities.collect { next ->
        if (next != mutable.value.identity) { mutable.value = NotebookScreenState(identity = next); if (next != null) refresh() }
    } } }
    fun edit(value: NotebookEditor?) { if (!mutable.value.busy) mutable.value = mutable.value.copy(editor = value, organization = null, reminderEditor = null) }
    fun editOrganization(value: NotebookOrganizationEditor) { if (!mutable.value.busy) mutable.value = mutable.value.copy(organization = value, editor = null, reminderEditor = null) }
    fun editReminder(value: NotebookReminderEditor?) { if (!mutable.value.busy) mutable.value = mutable.value.copy(reminderEditor = value, editor = null, organization = null) }
    fun clearEditors() { if (!mutable.value.busy) mutable.value = mutable.value.copy(editor = null, organization = null, reminderEditor = null) }
    fun openNewNote() { if (!mutable.value.busy) mutable.value = mutable.value.copy(editor = NotebookEditor(), organization = null, reminderEditor = null, message = null) }

    private fun say(owner: NotebookIdentity, text: String) {
        if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(message = text)
    }
    private fun action(failure: String, block: suspend (NotebookIdentity) -> Unit): kotlinx.coroutines.Job? {
        val owner = mutable.value.identity ?: return null
        if (mutable.value.busy) return null
        mutable.value = mutable.value.copy(busy = true)
        return viewModelScope.launch {
            try { block(owner) } catch (_: Exception) { say(owner, failure) }
            finally { if (mutable.value.identity == owner) mutable.value = mutable.value.copy(busy = false) }
        }
    }
    private suspend fun publish(owner: NotebookIdentity) {
        val snapshot = repository.snapshot(owner)
        val reminders = repository.reminders(owner)
        if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(notes = snapshot.notes, drafts = snapshot.drafts, reminders = reminders)
    }
    /** A [quiet] sync follows a save: offline, the saved-draft message stays instead of a sync failure. */
    private suspend fun syncNow(owner: NotebookIdentity, quiet: Boolean = false) {
        try {
            for (i in 0 until 20) { if (repository.queue.syncNext(owner) == "idle") break }
            repository.reader.refresh(owner)
            publish(owner)
            if (!quiet) say(owner, "Eşitleme tamamlandı. İşlem gerektiren taslaklar ayrıca gösterilir.")
        } catch (_: Exception) {
            runCatching { publish(owner) }
            if (!quiet) say(owner, "Eşitleme tamamlanamadı. Bekleyen işlemler aynı kimlikle yeniden denenecek.")
        }
    }
    fun refresh() { action("Eşitleme kullanılamıyor. Bu cihazdaki kaydedilmiş taslaklarınız korunuyor.") { owner ->
        publish(owner); repository.reader.refresh(owner); publish(owner)
        if (mutable.value.identity == owner) mutable.value = mutable.value.copy(message = null)
    } }
    fun sync() { action("Eşitleme tamamlanamadı. Bekleyen işlemler aynı kimlikle yeniden denenecek.") { owner -> syncNow(owner) } }

    /** Closing the editor keeps nothing when nothing was typed or changed; otherwise it saves the draft first. */
    fun finishEditor(onDone: () -> Unit = {}) {
        val editor = mutable.value.editor ?: return onDone()
        val empty = editor.version == 0L && editor.title.isBlank() && editor.body.isBlank()
        val unchanged = editor.pending == null && editor.originalTitle == editor.title && editor.originalBody == editor.body
        if (empty || unchanged) { clearEditors(); onDone(); return }
        save(onDone = onDone)
    }
    /** The draft is kept on this device first, then sent at once; [onDone] runs only once the editor has closed. */
    fun save(delete: Boolean = false, onDone: () -> Unit = {}) {
        val editor = mutable.value.editor ?: return
        val job = action("Kaydedilemedi. Metni kapatmadan uzunluğu, oturumu ve cihaz erişimini kontrol edin.") { owner ->
            val intent = NotebookMutation(UUID.randomUUID().toString(), editor.note, if (delete) "delete" else if (editor.pending != null) "resolve" else "sync",
                editor.version, if (delete) null else editor.title, if (delete) null else editor.body, editor.pending?.conflictID)
            if (editor.pending == null) repository.queue.stage(intent, owner)
            else repository.queue.resolveBlocked(editor.pending.intent.mutation, intent, owner)
            publish(owner)
            if (mutable.value.identity == owner) mutable.value = mutable.value.copy(editor = null,
                message = "Taslak bu cihazda kaydedildi. Eşitle ile sunucuya gönderebilirsiniz.")
            syncNow(owner, quiet = true)
        }
        job?.invokeOnCompletion { if (mutable.value.editor == null) viewModelScope.launch { onDone() } }
    }
    fun openOrganization(note: String, pending: NotebookPending? = null) {
        action("Checklist yüklenemedi veya not silinmiş. Kaydedilmiş taslaklar korunuyor.") { owner ->
            val data = repository.organization(note, owner); require(!data.tombstone)
            if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(editor = null, organization = NotebookOrganizationEditor(
                note, data.version, pending?.intent?.items ?: data.items, (pending?.intent?.tags ?: data.tags).joinToString(", "), pending?.intent?.mutation,
                if (pending == null) null else data.items.joinToString("\n") { (if (it.done) "✓ " else "○ ") + it.text } + "\n" + data.tags.joinToString(", ")))
        }
    }
    fun saveOrganization() {
        val data = mutable.value.organization ?: return
        action("Checklist kaydedilemedi. Boş/tekrar eden alanları ve uzunluk sınırlarını kontrol edin.") { owner ->
            val intent = NotebookMutation(UUID.randomUUID().toString(), data.note, "organize", data.version, null, null, null,
                data.items, if (data.tags.isBlank()) emptyList() else data.tags.split(',').map { it.trim() })
            if (data.pending == null) repository.queue.stage(intent, owner) else repository.queue.replaceOrganization(data.pending, intent, owner)
            publish(owner)
            if (mutable.value.identity == owner) mutable.value = mutable.value.copy(organization = null, message = "Checklist taslağı kaydedildi. Eşitle ile gönderin.")
        }
    }
    fun resolve(pending: NotebookPending) { action("Güncel sürüm alınamadı veya not silinmiş. Taslağınız korunuyor; eşitleyip yeniden deneyin.") { owner ->
        val (note, _) = repository.conflict(pending, owner)
        if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(editor = NotebookEditor(note.note_id, note.version,
            pending.intent.title ?: "", pending.intent.body ?: "", pending, (note.title ?: "") + "\n" + (note.body ?: "")))
    } }
    fun createReminder() {
        val editor = mutable.value.reminderEditor ?: return
        val owner = mutable.value.identity ?: return
        if (mutable.value.busy) return
        mutable.value = mutable.value.copy(busy = true)
        viewModelScope.launch {
            try {
                repository.createReminder(editor.title, editor.recurrence, editor.dueAt, owner, editor.note)
                publish(owner)
                if (mutable.value.identity == owner) mutable.value = mutable.value.copy(reminderEditor = null,
                    message = "Hatırlatıcı bu cihazın sunucu bildirimi kaydına bağlandı.")
            } catch (error: NotebookServerFailure) {
                say(owner, if (error.code == "DEVICE_UNAVAILABLE") "Bildirim izni ve güncel cihaz kaydı gerekli. Bildirimleri açıp yeniden deneyin."
                    else "Hatırlatıcı oluşturulamadı. Oturumu ve alanları kontrol edip yeniden deneyin.")
            } catch (_: Exception) { say(owner, "Hatırlatıcı oluşturulamadı. Bağlantıyı ve tarihi kontrol edip yeniden deneyin.") }
            finally { if (mutable.value.identity == owner) mutable.value = mutable.value.copy(busy = false) }
        }
    }
    fun settleReminder(operation: String, reminder: NotebookReminder, occurrence: NotebookReminderOccurrence? = null) {
        action("Hatırlatıcı değiştirilemedi. Güncel listeyi eşitleyip yeniden deneyin.") { owner ->
            val due = occurrence?.effective_due_at?.let { OffsetDateTime.parse(it).toInstant() }
            val snoozedUntil = if (operation == "snooze") maxOf(due ?: Instant.now(), Instant.now()).plusSeconds(10 * 60L) else null
            repository.settleReminder(operation, reminder, occurrence, snoozedUntil, owner)
            publish(owner)
            say(owner, when (operation) {
                "complete" -> "Hatırlatıcı tamamlandı."
                "snooze" -> "Hatırlatıcı 10 dakika ertelendi."
                else -> "Hatırlatıcı iptal edildi."
            })
        }
    }
}

private enum class NotebookSection(val title: String, val symbol: String) {
    notes("Notlar", "note.text"), reminders("Hatırlatıcılar", "bell"), drafts("Taslaklar", "icloud.slash")
}

private fun recurrenceLabel(value: String) = when (value) { "daily" -> "Her gün"; "weekly" -> "Her hafta"; "monthly" -> "Her ay"; else -> "Bir kez" }
private val recurrences = listOf("once", "daily", "weekly", "monthly")
private fun parseInstant(raw: String?) = raw?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
private fun preview(body: String?) = body.orEmpty().trim().ifEmpty { "Metin yok" }.replace("\n", " ")

/** Kişisel Notlar (iOS `NotebookDestination`): private notes, reminders and this device's unsent drafts. */
@Composable
fun NotebookScreen(onClose: () -> Unit, startWithNewNote: Boolean = false, model: NotebookViewModel = hiltViewModel()) {
    val state by model.state.collectAsState()
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmExit by remember { mutableStateOf(false) }
    var closeAfterExit by remember { mutableStateOf(false) }
    var section by remember { mutableStateOf(NotebookSection.notes) }
    var search by remember { mutableStateOf("") }
    LaunchedEffect(state.identity) { if (startWithNewNote && state.identity != null) model.openNewNote() }
    val back: () -> Unit = {
        when {
            state.organization != null || state.reminderEditor != null -> { closeAfterExit = false; confirmExit = true }
            state.editor != null -> model.finishEditor()
            else -> onClose()
        }
    }
    BackHandler(enabled = !state.busy) { if (confirmExit) confirmExit = false else if (confirmDelete) confirmDelete = false else back() }
    if (state.identity == null) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaText("Not defteri için oturum açın.")
            NovaButton("Kapat", onClose, symbol = "xmark")
        }
        return
    }
    Box(Modifier.fillMaxSize().testTag("notebook.screen")) {
        Column(Modifier.fillMaxSize().blur(if (confirmDelete || confirmExit) 7.dp else 0.dp)) {
            NotebookTopBar(state, back, model)
            when {
                state.organization != null -> OrganizationFields(state, model)
                state.reminderEditor != null -> ReminderFields(state, model)
                state.editor != null -> EditorFields(state, model) { confirmDelete = true }
                else -> NotebookLibrary(state, model, section, { section = it }, search, { search = it })
            }
        }
        if (state.busy) Box(Modifier.align(Alignment.Center).semantics { contentDescription = "İşlem sürüyor" }) { NovaSpinner(NovaColorToken.text.color(), size = 26.dp) }
    }
    NovaPopup(confirmExit, { confirmExit = false }, identifier = "notebook.exit") {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            NovaPopupHeading("Kaydedilmemiş değişiklikler", symbol = "exclamationmark.triangle")
            NovaText("Editördeki değişiklikleri kaydetmeden çıkmak istiyor musunuz? Daha önce kaydedilmiş taslaklar silinmez.")
            NovaButton("Kaydetmeden çık", { confirmExit = false; model.clearEditors(); if (closeAfterExit) onClose() }, Modifier.fillMaxWidth(),
                variant = NovaButtonVariant.Danger, symbol = "xmark")
            NovaButton("Düzenlemeye dön", { confirmExit = false }, Modifier.fillMaxWidth(), variant = NovaButtonVariant.Surface, symbol = "chevron.left")
        }
    }
    NovaPopup(confirmDelete, { confirmDelete = false }, identifier = "notebook.delete") {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            NovaPopupHeading("Not silinsin mi?", symbol = "trash")
            NovaText("İşlem önce cihazda saklanır. Sunucu onayladığında not diğer cihazlarda da silinir.")
            NovaButton("Sil", { confirmDelete = false; model.save(delete = true) }, Modifier.fillMaxWidth(), variant = NovaButtonVariant.Danger, symbol = "trash")
            NovaButton("Vazgeç", { confirmDelete = false }, Modifier.fillMaxWidth(), variant = NovaButtonVariant.Surface, symbol = "chevron.left")
        }
    }
}

@Composable
private fun RoundIcon(symbol: String, label: String, identifier: String? = null, onClick: () -> Unit) {
    Box(Modifier.size(42.dp).clip(CircleShape).background(NovaColorToken.surface.color(), CircleShape).novaRowPress(onClick = onClick)
        .semantics { contentDescription = label }.then(if (identifier != null) Modifier.testTag(identifier) else Modifier),
        contentAlignment = Alignment.Center) { NovaIcon(symbol, 16.dp) }
}

@Composable
private fun NotebookTopBar(state: NotebookScreenState, back: () -> Unit, model: NotebookViewModel) {
    val title = when {
        state.organization != null -> "Checklist ve Etiketler"; state.reminderEditor != null -> "Yeni Hatırlatıcı"
        state.editor != null -> "Not"; else -> "Kişisel Notlar"
    }
    val subtitle = when {
        state.organization != null -> "Not düzeni"; state.reminderEditor != null -> "Sunucu bildirimi"
        state.editor != null -> "Değişiklikler cihazda güvenle saklanır"; else -> "Yalnızca size ait · ${state.notes.size} not"
    }
    Column {
        Row(Modifier.fillMaxWidth().background(NovaColorToken.canvas.color()).padding(horizontal = 18.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            RoundIcon("chevron.left", if (state.editor == null && state.organization == null && state.reminderEditor == null) "Kapat" else "Notlara dön",
                onClick = back)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                NovaSizedText(title, 22f, FontWeight.Bold)
                NovaText(subtitle, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color(), maxLines = 1)
            }
            when {
                state.editor != null -> Box(Modifier.height(42.dp).clip(CircleShape).background(NovaColorToken.accentSoft.color(), CircleShape)
                    .novaRowPress { model.finishEditor() }.testTag("notebook.done").padding(horizontal = 15.dp), contentAlignment = Alignment.Center) {
                    NovaSizedText("Bitti", 15f, FontWeight.SemiBold, NovaColorToken.accentInk.color())
                }
                state.organization == null && state.reminderEditor == null -> {
                    RoundIcon("arrow.triangle.2.circlepath", "Eşitle", onClick = model::sync)
                    RoundIcon("square.and.pencil", "Yeni not", "notebook.add", model::openNewNote)
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(NovaColorToken.hairline.color()))
    }
}

@Composable
private fun NotebookMessage(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(NovaColorToken.statusInfoBg.color()).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon("info.circle.fill", 14.dp, tint = NovaColorToken.statusInfoInk.color())
        NovaText(text, style = NovaTypeToken.meta, color = NovaColorToken.statusInfoInk.color())
    }
}

@Composable
private fun LibraryHeading(title: String, detail: String, modifier: Modifier = Modifier) {
    Row(modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaSizedText(title, 17f, FontWeight.Bold)
        NovaSizedText(detail, 12f, FontWeight.Bold, NovaColorToken.textTertiary.color())
    }
}

@Composable
private fun NotebookEmpty(symbol: String, title: String, detail: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 42.dp, horizontal = 22.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaIcon(symbol, 28.dp, tint = NovaColorToken.textTertiary.color())
        NovaSizedText(title, 16f, FontWeight.Bold)
        NovaText(detail, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

@Composable
private fun NotebookLibrary(state: NotebookScreenState, model: NotebookViewModel, section: NotebookSection, onSection: (NotebookSection) -> Unit,
                            search: String, onSearch: (String) -> Unit) {
    val query = search.trim()
    val notes = state.notes.filter { query.isEmpty() || it.title.orEmpty().contains(query, true) || it.body.orEmpty().contains(query, true) }
        .sortedByDescending { parseInstant(it.updated_at) ?: Instant.MIN }
    val drafts = state.drafts.filter { query.isEmpty() || it.intent.title.orEmpty().contains(query, true) || it.intent.body.orEmpty().contains(query, true) }
    val reminders = state.reminders.filter { it.state == "active" && (query.isEmpty() || it.title.contains(query, true)) }
        .sortedBy { parseInstant(it.next_occurrence?.effective_due_at) ?: Instant.MAX }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 14.dp, bottom = 110.dp + novaTabBarInset),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().heightIn(min = 46.dp).clip(RoundedCornerShape(15.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(15.dp))
                .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(15.dp)).padding(horizontal = 14.dp).testTag("notebook.search"),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("magnifyingglass", 15.dp, tint = NovaColorToken.textTertiary.color())
                Box(Modifier.weight(1f)) {
                    if (search.isEmpty()) NovaText("Notlarda ara", color = NovaColorToken.textPlaceholder.color())
                    BasicTextField(search, onSearch, Modifier.fillMaxWidth(), singleLine = true,
                        textStyle = novaTextStyle(NovaTypeToken.body).copy(color = NovaColorToken.text.color()), cursorBrush = SolidColor(NovaColorToken.text.color()))
                }
                if (search.isNotEmpty()) Box(Modifier.size(32.dp).clip(CircleShape).novaRowPress { onSearch("") }
                    .semantics { contentDescription = "Aramayı temizle" }, contentAlignment = Alignment.Center) {
                    NovaIcon("xmark.circle.fill", 15.dp, tint = NovaColorToken.textMuted.color())
                }
            }
            Row(Modifier.fillMaxWidth().clip(CircleShape).background(NovaColorToken.surfaceMuted.color(), CircleShape).padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                NotebookSection.entries.forEach { item ->
                    val on = item == section
                    Row(Modifier.weight(1f).clip(CircleShape).background(if (on) NovaColorToken.inverse.color() else androidx.compose.ui.graphics.Color.Transparent, CircleShape)
                        .novaRowPress { onSection(item) }.testTag("notebook.section.${item.name}").padding(vertical = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                        val ink = if (on) NovaColorToken.onInverse.color() else NovaColorToken.textSecondary.color()
                        NovaIcon(item.symbol, 12.dp, tint = ink)
                        NovaSizedText(item.title, 12.5f, FontWeight.SemiBold, ink, maxLines = 1)
                        if (item == NotebookSection.drafts && state.drafts.isNotEmpty()) NovaSizedText("${state.drafts.size}", 10f, FontWeight.Bold, ink)
                    }
                }
            }
            state.message?.let { NotebookMessage(it) }
            when (section) {
                NotebookSection.notes -> {
                    if (drafts.isNotEmpty()) {
                        LibraryHeading("Cihazdaki Taslaklar", "${drafts.size}")
                        drafts.forEach { DraftRow(it, compact = true, model) }
                    }
                    LibraryHeading(if (query.isEmpty()) "Son Notlar" else "Arama Sonuçları", "${notes.size}")
                    if (notes.isEmpty() && drafts.isEmpty()) NotebookEmpty("note.text",
                        if (query.isEmpty()) "İlk notunuzu oluşturun" else "Eşleşen not bulunamadı",
                        if (query.isEmpty()) "Düşüncelerinizi, yapılacakları ve saha notlarını tek yerde tutun." else "Farklı bir sözcükle aramayı deneyin.")
                    else notes.forEach { note -> NoteRow(note, state.drafts.any { it.intent.note == note.note_id }, model) }
                }
                NotebookSection.drafts -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LibraryHeading("Bekleyen İşlemler", "${drafts.size}", Modifier.weight(1f))
                        if (state.drafts.isNotEmpty()) NovaText("Şimdi eşitle", Modifier.novaRowPress(onClick = model::sync), NovaTypeToken.buttonSm,
                            color = NovaColorToken.accentInk.color())
                    }
                    if (drafts.isEmpty()) NotebookEmpty("checkmark.icloud", "Tüm değişiklikler eşitlendi", "Çevrimdışı kaydettiğiniz notlar burada görünür.")
                    else drafts.forEach { DraftRow(it, compact = false, model) }
                }
                NotebookSection.reminders -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LibraryHeading("Yaklaşan Hatırlatıcılar", "${reminders.size}", Modifier.weight(1f))
                        Row(Modifier.novaRowPress { model.editReminder(NotebookReminderEditor()) }.testTag("notebook.reminder.add"),
                            horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("plus", 11.dp, tint = NovaColorToken.accentInk.color())
                            NovaText("Yeni", style = NovaTypeToken.buttonSm, color = NovaColorToken.accentInk.color())
                        }
                    }
                    if (reminders.isEmpty()) NotebookEmpty("bell", "Hatırlatıcı yok", "Bir nota bağlı veya bağımsız sunucu bildirimi oluşturabilirsiniz.")
                    else reminders.forEach { ReminderRow(it, model) }
                }
            }
        }
        Box(Modifier.align(Alignment.BottomEnd).padding(22.dp).padding(bottom = novaTabBarInset).size(58.dp).clip(CircleShape)
            .background(NovaColorToken.inverse.color(), CircleShape).novaRowPress(onClick = model::openNewNote)
            .semantics { contentDescription = "Yeni not" }, contentAlignment = Alignment.Center) {
            NovaIcon("square.and.pencil", 20.dp, tint = NovaColorToken.onInverse.color())
        }
    }
}

@Composable
private fun NoteRow(note: NotebookRecord, blocked: Boolean, model: NotebookViewModel) {
    var menu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(18.dp))
        .border(1.dp, NovaColorToken.hairline.color(), RoundedCornerShape(18.dp)).testTag("notebook.note.${note.note_id}")) {
        Row(Modifier.fillMaxWidth().novaRowPress(enabled = !blocked) {
            model.edit(NotebookEditor(note.note_id, note.version, note.title.orEmpty(), note.body.orEmpty()))
        }.padding(15.dp), horizontalArrangement = Arrangement.spacedBy(13.dp)) {
            Box(Modifier.size(46.dp, 54.dp).clip(RoundedCornerShape(12.dp)).background(NovaColorToken.accentSoft.color()), contentAlignment = Alignment.Center) {
                NovaIcon("note.text", 18.dp, tint = NovaColorToken.accentInk.color())
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                NovaSizedText(note.title?.ifEmpty { null } ?: "Başlıksız Not", 15f, FontWeight.Bold, maxLines = 1)
                NovaSizedText(preview(note.body), 13f, FontWeight.Normal, NovaColorToken.textSecondary.color(), maxLines = 2)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    parseInstant(note.updated_at)?.let {
                        NovaText(DateUtils.getRelativeTimeSpanString(it.toEpochMilli()).toString(), style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                    }
                    if (blocked) {
                        NovaIcon("icloud.slash", 10.dp, tint = NovaColorToken.textTertiary.color())
                        NovaText("Eşitleme bekliyor", style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                    }
                }
            }
            Box(Modifier.size(32.dp).clip(CircleShape).novaRowPress(enabled = !blocked) { menu = !menu }
                .semantics { contentDescription = "Not seçenekleri" }, contentAlignment = Alignment.Center) {
                NovaIcon(if (menu) "chevron.up" else "ellipsis", 13.dp, tint = NovaColorToken.textSubtle.color())
            }
        }
        // iOS offers these from the row's context menu; here the row's own menu button reveals them.
        if (menu) Row(Modifier.padding(start = 15.dp, end = 15.dp, bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaCompactActionButton("Checklist ve Etiketler", "checklist", Modifier.weight(1f)) { menu = false; model.openOrganization(note.note_id) }
            NovaCompactActionButton("Hatırlatıcı Ekle", "bell.badge", Modifier.weight(1f)) {
                menu = false; model.editReminder(NotebookReminderEditor(title = note.title.orEmpty(), note = note.note_id))
            }
        }
    }
}

@Composable
private fun DraftRow(pending: NotebookPending, compact: Boolean, model: NotebookViewModel) {
    val waiting = pending.blocked == null
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(NovaColorToken.statusWarningBg.color()).padding(15.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            val ink = if (waiting) NovaColorToken.statusWarningInk.color() else NovaColorToken.statusDangerInk.color()
            NovaIcon(if (waiting) "icloud.slash" else "exclamationmark.icloud", 12.dp, tint = ink)
            NovaText(if (waiting) "Gönderilmeyi bekliyor" else "İşlem gerekli", Modifier.weight(1f), NovaTypeToken.buttonSm, color = ink)
            if (pending.intent.action == "organize") NovaIcon("checklist", 13.dp)
        }
        NovaSizedText(pending.intent.title ?: when (pending.intent.action) {
            "organize" -> "Checklist ve etiket taslağı"; "delete" -> "Silme isteği"; else -> "Başlıksız Not"
        }, 15f, FontWeight.Bold, maxLines = 1)
        if (!compact) NovaSizedText(preview(pending.intent.body), 13f, FontWeight.Normal, NovaColorToken.textSecondary.color(), maxLines = 3)
        if (pending.blocked == "VERSION_CONFLICT" && pending.intent.action == "organize")
            NovaText("Checklist sürümlerini incele", Modifier.novaRowPress { model.openOrganization(pending.intent.note, pending) }, NovaTypeToken.buttonSm,
                color = NovaColorToken.accentInk.color())
        if (pending.conflictID != null) NovaText("İki sürümü incele", Modifier.novaRowPress { model.resolve(pending) }, NovaTypeToken.buttonSm,
            color = NovaColorToken.accentInk.color())
    }
}

@Composable
private fun ReminderRow(reminder: NotebookReminder, model: NotebookViewModel) {
    val due = parseInstant(reminder.next_occurrence?.effective_due_at)
    val schedule = due?.let { " · " + DateTimeFormatter.ofPattern("d MMM yyyy HH:mm", Locale.forLanguageTag("tr-TR")).format(it.atZone(ZoneId.systemDefault())) }.orEmpty()
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(NovaColorToken.surface.color()).padding(15.dp)
        .testTag("notebook.reminder.${reminder.reminder_id}"), verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(38.dp).clip(CircleShape).background(NovaColorToken.statusWarningBg.color()), contentAlignment = Alignment.Center) {
                NovaIcon("bell.fill", 15.dp, tint = NovaColorToken.statusWarningInk.color())
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaSizedText(reminder.title, 15f, FontWeight.Bold)
                NovaText(recurrenceLabel(reminder.recurrence) + schedule, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            reminder.next_occurrence?.let { occurrence ->
                NovaCompactActionButton("Tamamla", "checkmark", Modifier.weight(1f)) { model.settleReminder("complete", reminder, occurrence) }
                NovaCompactActionButton("10 dk ertele", "clock.arrow.circlepath", Modifier.weight(1f)) { model.settleReminder("snooze", reminder, occurrence) }
            }
            NovaCompactActionButton("İptal et", "bell.slash", Modifier.weight(1f)) { model.settleReminder("cancel", reminder) }
        }
    }
}

@Composable
private fun EditorFields(state: NotebookScreenState, model: NotebookViewModel, onDelete: () -> Unit) {
    val editor = state.editor ?: return
    val focus = remember { FocusRequester() }
    LaunchedEffect(editor.note) { if (editor.version == 0L) runCatching { focus.requestFocus() } }
    Column(Modifier.fillMaxSize()) {
        editor.serverText?.let { text ->
            Column(Modifier.fillMaxWidth().background(NovaColorToken.statusInfoBg.color()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("icloud", 12.dp); NovaText("Güncel sunucu sürümü", style = NovaTypeToken.buttonSm)
                }
                NovaText(text, style = NovaTypeToken.meta, maxLines = 4)
            }
        }
        state.message?.let { NotebookMessage(it, Modifier.padding(horizontal = 18.dp).padding(top = 12.dp)) }
        Column(Modifier.weight(1f).fillMaxWidth().background(NovaColorToken.surface.color()).verticalScroll(rememberScrollState())) {
            val ink = NovaColorToken.text.color()
            Box(Modifier.padding(horizontal = 20.dp).padding(top = 22.dp, bottom = 8.dp)) {
                if (editor.title.isEmpty()) NovaSizedText("Başlık", 27f, FontWeight.Bold, NovaColorToken.textPlaceholder.color())
                BasicTextField(editor.title, { model.edit(editor.copy(title = it)) }, Modifier.fillMaxWidth().focusRequester(focus).testTag("notebook.title"),
                    textStyle = novaTextStyle(NovaTypeToken.screenTitle).copy(fontSize = 27.sp, color = ink), cursorBrush = SolidColor(ink),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
            }
            Box(Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(1.dp).background(NovaColorToken.hairline.color()))
            Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
                if (editor.body.isEmpty()) NovaSizedText("Yazmaya başlayın…", 17f, FontWeight.Normal, NovaColorToken.textPlaceholder.color())
                BasicTextField(editor.body, { model.edit(editor.copy(body = it)) }, Modifier.fillMaxWidth().heightIn(min = 240.dp).testTag("notebook.body"),
                    textStyle = novaTextStyle(NovaTypeToken.body).copy(fontSize = 17.sp, lineHeight = 24.sp, color = ink), cursorBrush = SolidColor(ink),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(NovaColorToken.hairline.color()))
        Row(Modifier.fillMaxWidth().background(NovaColorToken.canvas.color()).navigationBarsPadding().padding(bottom = novaTabBarClearance)
            .heightIn(min = 54.dp).padding(horizontal = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val saved = editor.version > 0
            NovaCompactActionButton("Checklist", "checklist", Modifier.width(IntrinsicSize.Max), enabled = saved && editor.pending == null) {
                val note = editor.note
                model.finishEditor { model.openOrganization(note) }
            }
            NovaCompactActionButton("Hatırlat", "bell.badge", Modifier.width(IntrinsicSize.Max), enabled = saved) {
                val note = editor.note; val title = editor.title
                model.finishEditor { model.editReminder(NotebookReminderEditor(title = title, note = note)) }
            }
            Spacer(Modifier.weight(1f))
            NovaText("${editor.body.length} karakter", style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
            if (saved && editor.pending == null) Box(Modifier.size(40.dp).clip(CircleShape).novaRowPress(onClick = onDelete)
                .semantics { contentDescription = "Notu sil" }.testTag("notebook.delete"), contentAlignment = Alignment.Center) {
                NovaIcon("trash", 15.dp, tint = NovaColorToken.statusDangerInk.color())
            }
        }
    }
}

@Composable
private fun ReminderFields(state: NotebookScreenState, model: NotebookViewModel) {
    val editor = state.reminderEditor ?: return
    val context = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    val zone = ZoneId.systemDefault()
    val local = editor.dueAt.atZone(zone)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaCard(Modifier.fillMaxWidth(), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(46.dp).clip(CircleShape).background(NovaColorToken.statusWarningBg.color()), contentAlignment = Alignment.Center) {
                        NovaIcon("bell.badge.fill", 21.dp, tint = NovaColorToken.statusWarningInk.color())
                    }
                    NovaTextField("Hatırlatıcı başlığı", editor.title, { model.editReminder(editor.copy(title = it)) }, Modifier.weight(1f),
                        identifier = "notebook.reminder.title")
                }
                NovaDivider()
                NovaText("Tekrar", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                NovaSegmentedControl(recurrences.map(::recurrenceLabel), recurrences.indexOf(editor.recurrence).coerceAtLeast(0)) {
                    model.editReminder(editor.copy(recurrence = recurrences[it]))
                }
                NovaDivider()
                NovaDayField("Tarih", local.toLocalDate().toString(), { picked ->
                    runCatching { LocalDate.parse(picked) }.getOrNull()?.takeIf { !it.isBefore(LocalDate.now(zone)) }?.let {
                        model.editReminder(editor.copy(dueAt = it.atTime(local.toLocalTime()).atZone(zone).toInstant()))
                    }
                }, "notebook.reminder.date")
                NovaTimeField("Saat", local.toLocalTime().withSecond(0).withNano(0), "notebook.reminder.time") { time: LocalTime ->
                    model.editReminder(editor.copy(dueAt = local.toLocalDate().atTime(time).atZone(zone).toInstant()))
                }
            }
        }
        if (editor.note != null) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("link", 12.dp, tint = NovaColorToken.textSecondary.color())
            NovaText("Bu hatırlatıcı seçili nota bağlanacak", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        state.message?.let { NotebookMessage(it) }
        NovaButton("Bildirimleri aç / cihaz kaydını yenile", {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            else context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }, Modifier.fillMaxWidth(), variant = NovaButtonVariant.Surface, symbol = "bell.badge")
        NovaText("Teslimat sahibi: bu cihazdaki sunucu bildirimi kaydı. Bildirim izni veya güncel cihaz kaydı yoksa hatırlatıcı oluşturulmaz.",
            style = NovaTypeToken.metaQuiet)
        NovaButton("Hatırlatıcıyı oluştur", model::createReminder, Modifier.fillMaxWidth().testTag("notebook.reminder.create"),
            enabled = !state.busy && editor.title.isNotBlank(), symbol = "checkmark")
    }
}

@Composable
private fun OrganizationFields(state: NotebookScreenState, model: NotebookViewModel) {
    val organization = state.organization ?: return
    fun update(items: List<NotebookItem>) = model.editOrganization(organization.copy(items = items))
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        state.message?.let { NotebookMessage(it) }
        organization.serverText?.let { NovaCard(Modifier.fillMaxWidth(), padding = 18) { NovaText("Güncel sunucu checklist'i\n$it") } }
        NovaCard(Modifier.fillMaxWidth(), padding = 18) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NovaTextField("Etiketler (virgülle ayırın)", organization.tags, { model.editOrganization(organization.copy(tags = it)) },
                    identifier = "notebook.tags")
                organization.items.forEach { item ->
                    key(item.item_id) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Switch(item.done, { done -> update(organization.items.map { if (it.item_id == item.item_id) it.copy(done = done) else it }) },
                                Modifier.semantics { contentDescription = "Tamamlandı" },
                                colors = SwitchDefaults.colors(checkedTrackColor = NovaColorToken.accent.color()))
                            NovaTextField("Yapılacak", item.text, { text -> update(organization.items.map { if (it.item_id == item.item_id) it.copy(text = text) else it }) },
                                Modifier.weight(1f))
                            Box(Modifier.size(40.dp).clip(CircleShape).novaRowPress { update(organization.items.filterNot { it.item_id == item.item_id }) }
                                .semantics { contentDescription = "Checklist maddesini kaldır" }, contentAlignment = Alignment.Center) {
                                NovaIcon("minus.circle", 16.dp, tint = NovaColorToken.statusDangerInk.color())
                            }
                        }
                    }
                }
            }
        }
        NovaButton("Madde ekle", { update(organization.items + NotebookItem(UUID.randomUUID().toString(), "", false)) }, Modifier.fillMaxWidth(),
            variant = NovaButtonVariant.Surface, enabled = organization.items.size < 500, symbol = "plus")
        NovaButton("Checklist taslağını kaydet", model::saveOrganization, Modifier.fillMaxWidth(), symbol = "checkmark")
    }
}
