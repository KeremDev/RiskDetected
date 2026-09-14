package com.riskdetectedan.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.data.education.*
import com.riskdetectedan.core.data.company.PersonnelWorkspaceIdentity
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import javax.inject.Inject

data class EducationState(val rows: List<JsonObject> = emptyList(), val context: JsonObject? = null,
    val draft: JsonObject? = null, val saved: JsonObject? = null, val people: Map<String,List<JsonObject>> = emptyMap(),
    val certificate: JsonObject? = null, val busy: Boolean = false, val pending: Boolean = false, val error: String? = null)
@HiltViewModel class EducationViewModel @Inject constructor(private val repository: EducationRepository): ViewModel() {
    private val state = MutableStateFlow(EducationState()); val ui=state.asStateFlow()
    private var identity: PersonnelWorkspaceIdentity? = null
    private var work: Job? = null
    fun start(value: PersonnelWorkspaceIdentity) {
        if(identity==value)return
        work?.cancel(); identity=value; state.value=EducationState(); refresh()
    }
    private fun perform(task: suspend (PersonnelWorkspaceIdentity)->Unit) {
        val id=identity ?: return
        if(state.value.busy)return
        state.update { it.copy(busy=true,error=null) }
        work=viewModelScope.launch {
            try { task(id); repository.check(id) }
            catch(error: Exception) { currentCoroutineContext().ensureActive(); if(identity==id)state.update { it.copy(error=message(error)) } }
            finally { if(identity==id)state.update { it.copy(busy=false) } }
        }
    }
    fun refresh()=perform { id ->
        val context=repository.context(id); val rows=repository.list(id); val pending=repository.pending(id)
        state.update { it.copy(context=context,rows=rows,pending=pending!=null) }
    }
    fun open(row: JsonObject?)=perform { id ->
        val context=repository.context(id,row?.text("id")); val current=(context["row"] as? JsonObject) ?: row
        val pending=repository.pending(id)
        val draft=pending?.takeIf { it.text("action")!="curriculum" } ?: repository.draft(id,current?.text("id").orEmpty()) ?: current?.let { saved ->
            (saved["education"] as? JsonObject)?.let { edu ->
                edu.with("action","save").with("id",saved.getValue("id")).with("expected_version",saved.getValue("version")).with("title",saved.text("title")).with("notes",saved.text("notes"))
            }
        } ?: EducationRules.draft().let { new ->
            if(current==null)new else new.with("id",current.getValue("id")).with("expected_version",current.getValue("version")).with("title",current.text("title"))
        }
        val people=mutableMapOf<String,List<JsonObject>>()
        context.objects("workplaces").map { it.text("company_id") }.distinct().forEach { people[it]=repository.employees(id,it) }
        state.update { it.copy(context=context,draft=draft,saved=current,people=people,pending=pending!=null,certificate=null) }
    }
    fun edit(draft: JsonObject) {
        if(state.value.busy || state.value.pending)return
        state.update { it.copy(draft=draft,certificate=null) }
        val id=identity ?: return
        viewModelScope.launch { try { repository.preserve(id,draft) } catch(error: Exception) { currentCoroutineContext().ensureActive(); state.update { it.copy(error=message(error)) } } }
    }
    fun closeEditor() { if(!state.value.busy){ state.update { it.copy(draft=null,saved=null,certificate=null) }; refresh() } }
    fun save()=perform { id ->
        val draft=if(state.value.pending)repository.pending(id) else state.value.draft
        val receipt=try { repository.save(id,draft ?: return@perform) } catch(error: Exception) {
            currentCoroutineContext().ensureActive();val pending=repository.pending(id)!=null;state.update { it.copy(pending=pending) };throw error
        }
        val row=receipt["row"] as? JsonObject
        if(row!=null) {
            val education=row.getValue("education").jsonObject
            val updated=education.with("action","save").with("id",row.getValue("id")).with("expected_version",row.getValue("version")).with("title",row.text("title")).with("notes",row.text("notes"))
            state.update { it.copy(saved=row,draft=updated,pending=false) }
        } else state.update { it.copy(pending=false) }
    }
    fun curriculum(scope: JsonObject)=perform { id ->
        val draft=state.value.draft ?: return@perform
        repository.save(id,draft.with("action","curriculum").with("id",JsonNull).with("scopes",objects(listOf(scope))))
        val context=repository.context(id,state.value.saved?.text("id"))
        state.update { it.copy(context=context) }
    }
    fun certificate(scope: JsonObject, person: JsonObject, issue: Boolean)=perform { id ->
        val saved=state.value.saved ?: return@perform
        val known=state.value.context?.objects("certificates")?.firstOrNull { it.text("scope_id")==scope.text("id") && it.text("person_id")==person.text("id") && it["source_session_revision"]==saved["version"] }
        val result=repository.certificate(id,if(!issue && known!=null)buildJsonObject { put("action","read");put("document_id",known.getValue("document_id"));put("revision",known.getValue("revision")) } else buildJsonObject {
            put("action",if(issue)"issue" else "preview");put("session_id",saved.text("id"));put("scope_id",scope.text("id"));put("person_id",person.text("id"));put("expected_version",saved.getValue("version"))
        }, scope.text("logo_path").ifEmpty { null })
        state.update { it.copy(certificate=result) }
    }
    fun completeCertificateFields(draft: JsonObject)=perform { id ->
        val previous=state.value.certificate?.getValue("snapshot")?.jsonObject ?: return@perform
        repository.preserve(id,draft)
        val receipt=repository.save(id,draft)
        val row=receipt.getValue("row").jsonObject;val education=row.getValue("education").jsonObject
        val updated=education.with("action","save").with("id",row.getValue("id")).with("expected_version",row.getValue("version")).with("title",row.text("title")).with("notes",row.text("notes"))
        state.update { it.copy(saved=row,draft=updated) }
        val scopeID=previous.getValue("scope").jsonObject.text("id");val personID=previous.getValue("person").jsonObject.text("id")
        val result=repository.certificate(id,buildJsonObject { put("action","preview");put("session_id",row.text("id"));put("scope_id",scopeID);put("person_id",personID);put("expected_version",row.getValue("version")) },education.objects("scopes").firstOrNull { it.text("id")==scopeID }?.text("logo_path"))
        state.update { it.copy(certificate=result,context=state.value.context) }
    }
    fun readCertificate(document: JsonObject)=perform { id ->
        val result=repository.certificate(id,buildJsonObject { put("action","read");put("document_id",document.getValue("document_id"));put("revision",document.getValue("revision")) })
        state.update { it.copy(certificate=result) }
    }
    fun dismissCertificate(){state.update { it.copy(certificate=null) }}
    suspend fun authorize() { repository.check(identity ?: throw EducationFailure("ACCESS_DENIED")) }
    private fun message(error: Exception): String = when((error as? EducationFailure)?.code) {
        "FEATURE_UNAVAILABLE" -> "Yeni eğitim modülü bu hesapta henüz açılmadı."
        "VERSION_CONFLICT" -> "Kayıt başka cihazda değişti. Güncel kaydı açın; taslağınız korunur."
        "PARTICIPANT_DUPLICATE" -> "Bir personeli yalnız bir kapsama ekleyin."
        "TRAINING_DATE_INVALID","LESSON_OVERLAP_OR_FUTURE" -> "Gerçekleşen ders saatlerini ve çakışmaları kontrol edin."
        "PENDING_OPERATION" -> "Bekleyen işlemi önce tamamlayın."
        "ACCESS_DENIED" -> "Oturum veya firma erişimi değişti."
        else -> "İşlem tamamlanamadı. Bilgileri kontrol edip tekrar deneyin."
    }
}
