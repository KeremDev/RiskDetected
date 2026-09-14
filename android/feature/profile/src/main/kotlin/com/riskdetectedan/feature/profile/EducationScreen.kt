package com.riskdetectedan.feature.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.education.*
import com.riskdetectedan.core.data.company.PersonnelWorkspaceIdentity
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.serialization.json.*
import java.time.*
import java.util.UUID

@Composable internal fun EducationScreen(identity: PersonnelWorkspaceIdentity, canWrite: Boolean, onBack: ()->Unit, vm: EducationViewModel = hiltViewModel()) {
    val state by vm.ui.collectAsState()
    var query by remember { mutableStateOf("") }; var cycle by remember { mutableStateOf("") }; var company by remember { mutableStateOf("") }; var date by remember { mutableStateOf("") }
    LaunchedEffect(identity) { vm.start(identity) }
    BackHandler { if(state.draft!=null)vm.closeEditor() else onBack() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Row { Text("Eğitimler",style=MaterialTheme.typography.headlineSmall); Spacer(Modifier.weight(1f)); IconButton(onBack){Icon(Icons.Outlined.Close,"Kapat")} }
        if(state.busy)LinearProgressIndicator(Modifier.fillMaxWidth())
        state.error?.let { Text(it,color=MaterialTheme.colorScheme.error); TextButton(vm::refresh){Text("Yenile")} }
        EducationInput("Eğitim veya eğitici ara",query,{query=it})
        EducationChoice("Firma",company,linkedMapOf("" to "Tüm firmalar") + state.context?.objects("workplaces").orEmpty().associate { it.text("company_id") to it.text("company_name").ifEmpty { it.text("name") } }) { company=it }
        EducationChoice("Tür",cycle,linkedMapOf("" to "Tüm eğitimler") + EducationRules.cycles){cycle=it}
        EducationInput("Tarih (YYYY-AA-GG, isteğe bağlı)",date,{date=it})
        Button({vm.open(null)},enabled=canWrite && !state.busy && state.context?.flag("catalog_enabled")==true){Text(if(state.pending)"Bekleyen işlemi aç" else "Eğitim Ekle")}
        state.rows.filter { row ->
            (query.isEmpty() || (row.text("title")+row.text("trainer")).contains(query,true)) && (date.isEmpty() || row.text("held_on").startsWith(date)) &&
                (company.isEmpty() || row.objects("companies").any { it.text("company_id")==company }) &&
                (cycle.isEmpty() || (row["education"] as? JsonObject)?.objects("scopes")?.any { it.text("cycle")==cycle }==true)
        }.sortedByDescending { it.text("held_on") }.forEach { row ->
            OutlinedButton({vm.open(row)},Modifier.fillMaxWidth(),enabled=!state.busy) { Column { Text(row.text("title")); Text(row.text("held_on")+" · "+row.objects("companies").joinToString { it.text("company_name") },style=MaterialTheme.typography.bodySmall) } }
        }
    }
    state.draft?.let { draft ->
        Dialog(vm::closeEditor,properties=DialogProperties(usePlatformDefaultWidth=false,dismissOnClickOutside=false)) {
            Surface(Modifier.fillMaxWidth(.94f).fillMaxHeight(.9f),shape=MaterialTheme.shapes.large) {
                Column(Modifier.verticalScroll(rememberScrollState()).padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    Row { Text("Gerçekleşen eğitim",style=MaterialTheme.typography.titleLarge); Spacer(Modifier.weight(1f)); IconButton(vm::closeEditor){Icon(Icons.Outlined.Close,"Kapat")} }
                    state.error?.let { Text(it,color=MaterialTheme.colorScheme.error) }
                    if(state.busy)LinearProgressIndicator(Modifier.fillMaxWidth())
                    val enabled=canWrite && state.context?.flag("catalog_enabled")==true && !state.busy && !state.pending
                    EducationInput("Eğitim başlığı",draft.text("title"),{vm.edit(draft.with("title",it))},enabled)
                    EducationInput("Düzenleyici kişi / kurum",draft.text("provider_name"),{vm.edit(draft.with("provider_name",it))},enabled)
                    EducationSection("Eğiticiler") {
                        draft.objects("trainers").forEachIndexed { index,trainer ->
                            EducationInput("Ad soyad",trainer.text("name"),{vm.edit(replace(draft,"trainers",index,trainer.with("name",it)))},enabled)
                            EducationInput("Unvan / belge bilgisi",trainer.text("title"),{vm.edit(replace(draft,"trainers",index,trainer.with("title",it)))},enabled)
                        }
                        TextButton({vm.edit(draft.with("trainers",objects(draft.objects("trainers")+buildJsonObject { put("id",UUID.randomUUID().toString());put("name","");put("title","") })))},enabled=enabled){Text("Eğitici ekle")}
                    }
                    draft.objects("scopes").forEachIndexed { index,scope -> key(scope.text("id")) {
                        EducationScopeForm(scope,state.context!!,draft.objects("trainers"),state.people[scope.text("company_id")].orEmpty(),
                            draft.objects("scopes").filterIndexed { n,_->n!=index }.flatMap { it.objects("participants").map { p->p.text("id") } }.toSet(),enabled,
                            {vm.edit(replace(draft,"scopes",index,it))},{vm.curriculum(scope)}, {vm.edit(draft.with("scopes",objects(draft.objects("scopes").filterIndexed { n,_->n!=index })))})
                    } }
                    EducationChoice("Firma / görev kapsamı ekle","",state.context?.objects("workplaces").orEmpty().associate { it.text("id") to (it.text("company_name")+" · "+it.text("name")) },enabled) { selected ->
                        val wp=state.context!!.objects("workplaces").first { it.text("id")==selected }
                        var scope=EducationRules.scope(wp,state.context!!.getValue("package").jsonObject)
                        val curriculum=state.context!!.objects("curricula").firstOrNull { it.text("company_id")==wp.text("company_id") && it.text("workplace_id")==wp.text("id") && it.text("scope_key")=="initial:Genel:"+wp.text("hazard_class") }?.get("education") as? JsonObject
                        if(curriculum!=null)scope=scope.with("topics",objects(curriculum.objects("topics").map { it.with("trainer_ids",JsonArray(emptyList())) })).with("context_note",curriculum.text("context_note"))
                        vm.edit(draft.with("scopes",objects(draft.objects("scopes")+scope)))
                    }
                    Button(vm::save,enabled=canWrite && !state.busy && draft.objects("scopes").isNotEmpty()){Text(if(state.pending)"Bekleyen işlemi tamamla" else "Gerçekleşen eğitimi kaydet")}
                    val saved=state.saved
                    if(saved!=null && saved["education"] is JsonObject) {
                        val education=saved.getValue("education").jsonObject
                        val unchanged=draft["scopes"]==education["scopes"] && draft["trainers"]==education["trainers"] && draft["provider_name"]==education["provider_name"] && draft["title"]==saved["title"]
                        Text("Kişisel belgeler",style=MaterialTheme.typography.titleMedium)
                        if(!unchanged)Text("Sertifika için değişiklikleri kaydedin.")
                        education.objects("scopes").forEach { scope -> scope.objects("participants").forEach { person ->
                            OutlinedButton({vm.certificate(scope,person,false)},enabled=unchanged && !state.busy){Text(person.text("name")+" · Sertifika hazırla / aç")}
                            state.context?.objects("certificates").orEmpty().filter { it.text("scope_id")==scope.text("id") && it.text("person_id")==person.text("id") }.forEach { document ->
                                TextButton({vm.readCertificate(document)},enabled=!state.busy){Text("Belge revizyonu "+document.number("revision"))}
                            }
                        } }
                    } else if(saved!=null)Text("Eski kayıt: yeni sertifika için gerçekleşen içeriği ve saatleri uzman bilgisiyle tamamlayın.")
                }
            }
        }
    }
    state.certificate?.let { certificate ->
        EducationCertificateDialog(certificate,state.busy,state.context?.flag("certificate_enabled")==true && canWrite,vm::dismissCertificate,
            { val snapshot=certificate.getValue("snapshot").jsonObject; vm.certificate(snapshot.getValue("scope").jsonObject,snapshot.getValue("person").jsonObject,true) },vm::authorize,state.draft,vm::completeCertificateFields)
    }
}
internal fun replace(parent: JsonObject,key: String,index: Int,value: JsonObject) = parent.with(key,objects(parent.objects(key).mapIndexed { n,v->if(n==index)value else v }))
@Composable internal fun EducationInput(label: String,value: String,onChange: (String)->Unit,enabled: Boolean=true) {
    OutlinedTextField(value,onChange,Modifier.fillMaxWidth(),label={Text(label)},enabled=enabled)
}
@Composable internal fun EducationChoice(label: String,value: String,choices: Map<String,String>,enabled: Boolean=true,onSelect: (String)->Unit) {
    var open by remember { mutableStateOf(false) }
    Box { OutlinedButton({open=true},enabled=enabled,modifier=Modifier.fillMaxWidth()){Text("$label: ${choices[value].orEmpty()}")}
        DropdownMenu(open,{open=false}) { choices.forEach { (key,title)->DropdownMenuItem(text={Text(title)},onClick={open=false;onSelect(key)}) } }
    }
}
@Composable internal fun EducationSection(title: String,content: @Composable ColumnScope.()->Unit) {
    var expanded by remember { mutableStateOf(false) }
    OutlinedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        TextButton({expanded=!expanded}){Text((if(expanded)"− " else "+ ")+title)}
        if(expanded)content()
    } }
}
