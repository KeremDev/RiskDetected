package com.riskdetectedan.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.activity.compose.BackHandler
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.notebook.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import java.util.UUID

object NotebookUIRelease { const val enabled = false }
data class NotebookEditor(val note: String = UUID.randomUUID().toString(), val version: Long = 0,
    val title: String = "", val body: String = "", val pending: NotebookPending? = null, val serverText: String? = null)
data class NotebookScreenState(val identity: NotebookIdentity? = null, val notes: List<NotebookRecord> = emptyList(),
    val drafts: List<NotebookPending> = emptyList(), val busy: Boolean = false, val message: String? = null, val editor: NotebookEditor? = null,
    val organization: NotebookOrganizationEditor? = null)
data class NotebookOrganizationEditor(val note: String, val version: Long, val items: List<NotebookItem>, val tags: String,
    val pending: String? = null, val serverText: String? = null)

@HiltViewModel
class NotebookViewModel @Inject constructor(private val repository: NotebookRepository) : ViewModel() {
    private val mutable = MutableStateFlow(NotebookScreenState())
    val state = mutable.asStateFlow()
    init { viewModelScope.launch { repository.identities.collect { next ->
        if (next != mutable.value.identity) { mutable.value = NotebookScreenState(identity = next); if (next != null) refresh() }
    } } }
    fun edit(value: NotebookEditor?) { if (!mutable.value.busy) mutable.value = mutable.value.copy(editor = value, organization = null) }
    fun editOrganization(value: NotebookOrganizationEditor) { if (!mutable.value.busy) mutable.value = mutable.value.copy(organization = value, editor = null) }
    fun openOrganization(note: String, pending: NotebookPending? = null) = action { owner ->
        val data = repository.organization(note, owner); require(!data.tombstone)
        if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(organization = NotebookOrganizationEditor(
            note, data.version, pending?.intent?.items ?: data.items, (pending?.intent?.tags ?: data.tags).joinToString(", "), pending?.intent?.mutation,
            if (pending == null) null else data.items.joinToString("\n") { (if (it.done) "✓ " else "○ ") + it.text } + "\n" + data.tags.joinToString(", ")))
    }
    fun saveOrganization() {
        val data = mutable.value.organization ?: return
        action { owner ->
            val intent = NotebookMutation(UUID.randomUUID().toString(), data.note, "organize", data.version, null, null, null,
                data.items, if (data.tags.isBlank()) emptyList() else data.tags.split(',').map { it.trim() })
            if (data.pending == null) repository.queue.stage(intent, owner) else repository.queue.replaceOrganization(data.pending, intent, owner)
            publish(owner)
            if (mutable.value.identity == owner) mutable.value = mutable.value.copy(organization = null, message = "Checklist taslağı kaydedildi. Eşitle ile gönderin.")
        }
    }
    private fun action(block: suspend (NotebookIdentity) -> Unit) {
        val owner = mutable.value.identity ?: return
        if (mutable.value.busy) return
        mutable.value = mutable.value.copy(busy = true)
        viewModelScope.launch {
            try { block(owner) }
            catch (_: Exception) {
                if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(message = "İşlem tamamlanamadı. Kaydedilmiş taslaklarınız korunuyor; yeniden deneyebilirsiniz.")
            } finally { if (mutable.value.identity == owner) mutable.value = mutable.value.copy(busy = false) }
        }
    }
    private suspend fun publish(owner: NotebookIdentity) {
        val snapshot = repository.snapshot(owner)
        if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(notes = snapshot.notes, drafts = snapshot.drafts)
    }
    fun refresh() = action { owner -> publish(owner); repository.reader.refresh(owner); publish(owner) }
    fun sync() = action { owner ->
        try {
            for (i in 0 until 20) { if (repository.queue.syncNext(owner) == "idle") break }
            repository.reader.refresh(owner)
        } finally { publish(owner) }
    }
    fun save(delete: Boolean = false) {
        val editor = mutable.value.editor ?: return
        action { owner ->
            val intent = NotebookMutation(UUID.randomUUID().toString(), editor.note, if (delete) "delete" else if (editor.pending != null) "resolve" else "sync",
                editor.version, if (delete) null else editor.title, if (delete) null else editor.body, editor.pending?.conflictID)
            if (editor.pending == null) repository.queue.stage(intent, owner)
            else repository.queue.resolveBlocked(editor.pending.intent.mutation, intent, owner)
            publish(owner)
            if (mutable.value.identity == owner) mutable.value = mutable.value.copy(editor = null, message = "Taslak bu cihazda kaydedildi. Eşitle ile sunucuya gönderebilirsiniz.")
        }
    }
    fun resolve(pending: NotebookPending) = action { owner ->
        val (note, _) = repository.conflict(pending, owner)
        if (repository.identity() == owner && mutable.value.identity == owner) mutable.value = mutable.value.copy(editor = NotebookEditor(note.note_id, note.version,
            pending.intent.title ?: "", pending.intent.body ?: "", pending, (note.title ?: "") + "\n" + (note.body ?: "")))
    }
}

@Composable
fun NotebookScreen(onClose: () -> Unit, model: NotebookViewModel = hiltViewModel()) {
    val state by model.state.collectAsState()
    var deleteConfirmation by remember(state.identity) { mutableStateOf(false) }
    var exitConfirmation by remember(state.identity) { mutableStateOf(false) }
    var closeAfterExit by remember(state.identity) { mutableStateOf(false) }
    fun requestClose() { if (state.editor == null && state.organization == null) onClose() else { closeAfterExit = true; exitConfirmation = true } }
    BackHandler { if (!state.busy) requestClose() }
    val green = Color(0xFF23CE50)
    Column(Modifier.fillMaxSize().background(Color(0xFFEFEFEF)).blur(if (deleteConfirmation || exitConfirmation) 7.dp else 0.dp).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NoteAction("Kapat", Icons.Outlined.Close, !state.busy) { requestClose() }
        Text("Kişisel Notlar", style = MaterialTheme.typography.headlineMedium)
        Text("Ücretsiz · Yalnız size ait · Firmalardan bağımsız", color = Color.Gray)
        if (state.identity == null) Text("Not defteri için oturum açın.")
        else {
            state.message?.let { NoteCard { Text(it) } }
            if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth(), color = green)
            val editor = state.editor
            val organization = state.organization
            if (organization != null) {
                organization.serverText?.let { NoteCard { Text("Güncel sunucu checklist'i"); Text(it) } }
                NoteCard {
                    OutlinedTextField(organization.tags, { model.editOrganization(organization.copy(tags = it)) }, label = { Text("Etiketler (virgülle ayırın)") }, enabled = !state.busy)
                    organization.items.forEach { item -> key(item.item_id) {
                        Row {
                            Checkbox(item.done, { done -> model.editOrganization(organization.copy(items = organization.items.map { if (it.item_id == item.item_id) it.copy(done = done) else it })) }, enabled = !state.busy)
                            OutlinedTextField(item.text, { text -> model.editOrganization(organization.copy(items = organization.items.map { if (it.item_id == item.item_id) it.copy(text = text) else it })) }, enabled = !state.busy, modifier = Modifier.weight(1f))
                            IconButton(onClick = { model.editOrganization(organization.copy(items = organization.items.filterNot { it.item_id == item.item_id })) }, enabled = !state.busy) {
                                Icon(Icons.Outlined.RemoveCircleOutline, "Checklist maddesini kaldır", tint = green)
                            }
                        }
                    } }
                }
                NoteAction("Madde ekle", Icons.Outlined.Add, !state.busy && organization.items.size < 500) { model.editOrganization(organization.copy(items = organization.items + NotebookItem(UUID.randomUUID().toString(), "", false))) }
                NoteAction("Checklist taslağını kaydet", Icons.Outlined.Check, !state.busy, model::saveOrganization)
                NoteAction("Listeye dön", Icons.Outlined.ArrowBack, !state.busy) { closeAfterExit = false; exitConfirmation = true }
            } else if (editor != null) {
                editor.serverText?.let { NoteCard { Text("Güncel sunucu sürümü"); Text(it) } }
                NoteCard {
                    OutlinedTextField(editor.title, { model.edit(editor.copy(title = it)) }, label = { Text("Başlık") }, enabled = !state.busy, modifier = Modifier.fillMaxWidth().testTag("notebook.title"))
                    OutlinedTextField(editor.body, { model.edit(editor.copy(body = it)) }, label = { Text("Not") }, minLines = 7, enabled = !state.busy, modifier = Modifier.fillMaxWidth().testTag("notebook.body"))
                    Text("Başlık en çok 200, metin en çok 20.000 karakter.", color = Color.Gray)
                }
                NoteAction("Taslağı güvenle kaydet", Icons.Outlined.Check, !state.busy) { model.save() }
                if (editor.version > 0 && editor.pending == null) NoteAction("Notu sil", Icons.Outlined.Delete, !state.busy) { deleteConfirmation = true }
                NoteAction("Listeye dön", Icons.Outlined.ArrowBack, !state.busy) { closeAfterExit = false; exitConfirmation = true }
            } else {
                NoteAction("Yeni not", Icons.Outlined.EditNote, !state.busy) { model.edit(NotebookEditor()) }
                NoteAction("Eşitle", Icons.Outlined.Sync, !state.busy, model::sync)
                if (state.notes.isEmpty() && state.drafts.isEmpty()) NoteCard { Icon(Icons.Outlined.Note, null, tint = green); Text("Henüz not yok") }
                state.drafts.forEach { draft ->
                    key(draft.intent.mutation) { NoteCard {
                        Text(if (draft.blocked == null) "Gönderilmeyi bekliyor" else "Taslağınız korunuyor · işlem gerekli")
                        Text(draft.intent.title ?: "Başlıksız not", style = MaterialTheme.typography.titleMedium)
                        Text(draft.intent.body ?: if (draft.intent.action == "organize") "Checklist ve etiket taslağı" else "Silme isteği")
                        if (draft.intent.action == "organize") {
                            Text((draft.intent.items ?: emptyList()).joinToString("\n") { (if (it.done) "✓ " else "○ ") + it.text })
                            Text((draft.intent.tags ?: emptyList()).joinToString(", "))
                            if (draft.blocked == "VERSION_CONFLICT") NoteAction("Checklist sürümlerini incele", Icons.Outlined.Checklist, !state.busy) { model.openOrganization(draft.intent.note, draft) }
                        }
                        if (draft.conflictID != null) NoteAction("İki sürümü incele", Icons.Outlined.CompareArrows, !state.busy) { model.resolve(draft) }
                    } }
                }
                state.notes.forEach { note ->
                    key(note.note_id) { NoteCard {
                        Text(note.title?.ifEmpty { "Başlıksız not" } ?: "Başlıksız not", style = MaterialTheme.typography.titleMedium)
                        Text(note.body ?: "", maxLines = 3)
                        NoteAction("Düzenle", Icons.Outlined.Edit, !state.busy && state.drafts.none { it.intent.note == note.note_id }) {
                            model.edit(NotebookEditor(note.note_id, note.version, note.title ?: "", note.body ?: ""))
                        }
                        NoteAction("Checklist ve etiketler", Icons.Outlined.Checklist, !state.busy && state.drafts.none { it.intent.note == note.note_id }) { model.openOrganization(note.note_id) }
                    } }
                }
            }
        }
    }
    if (exitConfirmation) Dialog(onDismissRequest = { exitConfirmation = false }) {
        Surface(shape = RoundedCornerShape(28.dp), color = Color(0xFFEFEFEF)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Kaydedilmemiş değişiklikler", style = MaterialTheme.typography.titleLarge)
                Text("Editördeki değişiklikleri kaydetmeden çıkmak istiyor musunuz? Daha önce kaydedilmiş taslaklar silinmez.")
                NoteAction("Kaydetmeden çık", Icons.Outlined.Close, true) { exitConfirmation = false; model.edit(null); if (closeAfterExit) onClose() }
                NoteAction("Düzenlemeye dön", Icons.Outlined.Edit, true) { exitConfirmation = false }
            }
        }
    }
    if (deleteConfirmation) Dialog(onDismissRequest = { deleteConfirmation = false }) {
        Surface(shape = RoundedCornerShape(28.dp), color = Color(0xFFEFEFEF)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Not silinsin mi?", style = MaterialTheme.typography.titleLarge)
                Text("İşlem önce cihazda saklanır. Sunucu onayladığında not diğer cihazlarda da silinir.")
                NoteAction("Sil", Icons.Outlined.Delete, true) { deleteConfirmation = false; model.save(true) }
                NoteAction("Vazgeç", Icons.Outlined.Close, true) { deleteConfirmation = false }
            }
        }
    }
}
@Composable private fun NoteCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), color = Color.White) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
}
@Composable private fun NoteAction(label: String, icon: ImageVector, enabled: Boolean, action: () -> Unit) {
    TextButton(onClick = action, enabled = enabled) {
        Icon(icon, null, tint = if (enabled) Color(0xFF12943B) else Color.Gray)
        Spacer(Modifier.width(10.dp)); Text(label, color = if (enabled) Color(0xFF171717) else Color.Gray)
    }
}
