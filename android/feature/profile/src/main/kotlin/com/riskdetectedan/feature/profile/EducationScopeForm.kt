package com.riskdetectedan.feature.profile

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.education.*
import kotlinx.serialization.json.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

@Composable internal fun EducationScopeForm(scope: JsonObject, context: JsonObject, trainers: List<JsonObject>, people: List<JsonObject>, excluded: Set<String>, enabled: Boolean,
    change: (JsonObject)->Unit, curriculum: ()->Unit, remove: ()->Unit) {
    val topics=scope.objects("topics");val basic=EducationRules.basic(scope.text("cycle"));var search by remember { mutableStateOf("") };var error by remember { mutableStateOf<String?>(null) }
    fun defaults(cycle: String): JsonObject {
        val saved=context.objects("curricula").firstOrNull { it.text("company_id")==scope.text("company_id") && it.text("workplace_id")==scope.text("workplace_id") && it.text("scope_key")==cycle+":"+scope.text("group_name")+":"+scope.text("hazard_class") }?.get("education") as? JsonObject
        val topics=saved?.objects("topics") ?: EducationRules.topics(context.getValue("package").jsonObject,cycle,scope.text("hazard_class"))
        return scope.with("topics",objects(topics.map { it.with("trainer_ids",JsonArray(emptyList())) })).with("context_note",saved?.text("context_note").orEmpty())
    }
    EducationSection(scope.text("company_name")+" · "+scope.text("group_name")+" · "+topics.sumOf { it.number("instruction_minutes") }+" dk") {
        EducationInput("Görev / içerik grubu",scope.text("group_name"),{change(scope.with("group_name",it))},enabled)
        EducationChoice("Tür / döngü",scope.text("cycle"),EducationRules.cycles,enabled){change(scope.with("cycle",it))}
        Text("Tür değişiminde mevcut dakikalar korunur. İsterseniz varsayılanları getirin.",style=MaterialTheme.typography.bodySmall)
        EducationSection("Personeller (${scope.objects("participants").size})") {
            EducationInput("Personel ara",search,{search=it})
            people.filter { search.isEmpty() || it.text("name").contains(search,true) }.forEach { person ->
                val selected=scope.objects("participants").any { it.text("id")==person.text("id") }
                Row { Checkbox(selected,{ on->
                    val rest=scope.objects("participants").filter { it.text("id")!=person.text("id") }
                    val next=if(on)rest+buildJsonObject { put("id",person.text("id"));put("name",person.text("name"));put("job_title","") } else rest
                    change(scope.with("participants",objects(next)))
                },enabled=enabled && person.text("id") !in excluded);Text(person.text("name")) }
            }
            scope.objects("participants").forEachIndexed { index,person->
                EducationInput(person.text("name")+" · Belgeye özel unvan",person.text("job_title"),{change(replace(scope,"participants",index,person.with("job_title",it)))},enabled)
            }
            Text("Belge unvanı güncel personel görev kaydını değiştirmez.",style=MaterialTheme.typography.bodySmall)
        }
        listOf("G1","G2","G3","G4").forEach { group ->
            EducationSection("$group · ${topics.filter { it.text("group")==group }.sumOf { it.number("instruction_minutes") }} dk") {
                topics.forEachIndexed { index,topic->if(topic.text("group")==group) {
                    if(group=="G4" || !basic || topic.text("parent_code").isNotEmpty())EducationInput("Konu başlığı",topic.text("title"),{change(replace(scope,"topics",index,topic.with("title",it)))},enabled)
                    else Text(topic.text("code")+" · "+topic.text("title"))
                    Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        TextButton({change(replace(scope,"topics",index,topic.with("instruction_minutes",(topic.number("instruction_minutes")-5).coerceAtLeast(0))))},enabled=enabled){Text("−5")}
                        OutlinedTextField(topic.number("instruction_minutes").toString(),{it.toIntOrNull()?.takeIf { n->n in 0..1440 }?.let { n->change(replace(scope,"topics",index,topic.with("instruction_minutes",n))) }},Modifier.weight(1f),label={Text("Dakika")},enabled=enabled)
                        TextButton({change(replace(scope,"topics",index,topic.with("instruction_minutes",(topic.number("instruction_minutes")+5).coerceAtMost(1440))))},enabled=enabled){Text("+5")}
                    }
                    EducationChoice("Yöntem",topic.text("method"),mapOf("face_to_face" to "Yüz yüze","online" to "Online"),enabled){change(replace(scope,"topics",index,topic.with("method",it)))}
                    trainers.forEach { trainer->Row {
                        Checkbox(trainer.text("id") in topic.strings("trainer_ids"),{checked->
                            val ids=topic.strings("trainer_ids").filter { it!=trainer.text("id") }.toMutableList();if(checked)ids.add(trainer.text("id"))
                            change(replace(scope,"topics",index,topic.with("trainer_ids",JsonArray(ids.map(::JsonPrimitive)))))
                        },enabled=enabled);Text(trainer.text("name").ifEmpty { "Adsız eğitici" })
                    } }
                    if(group!="G4")TextButton({
                        val parent=topic.text("parent_code").ifEmpty { topic.text("code") }
                        val a=topic.with("code",parent+"-"+UUID.randomUUID()).with("parent_code",parent)
                        val b=a.with("code",parent+"-"+UUID.randomUUID()).with("title","Alt konu").with("instruction_minutes",0)
                        change(scope.with("topics",objects(topics.take(index)+listOf(a,b)+topics.drop(index+1))))
                    },enabled=enabled){Text("Alt konulara ayır")}
                    if(group=="G4" || !basic || topic.text("parent_code").isNotEmpty())TextButton({change(scope.with("topics",objects(topics.filterIndexed { n,_->n!=index })))},enabled=enabled){Text("Konuyu kaldır")}
                    HorizontalDivider()
                } }
            }
        }
        TextButton({change(scope.with("topics",objects(topics+EducationRules.topic("G4-"+UUID.randomUUID(),"G4","",0))))},enabled=enabled){Text("İşyerine özgü konu ekle")}
        EducationInput("İşyeri / görev ve risk dayanağı",scope.text("context_note"),{change(scope.with("context_note",it))},enabled)
        Text(if(scope.text("cycle")=="initial")"İlk eğitim dakikaları rehber örneğidir." else "Tekrar eğitimindeki dakika dağılımı ürün önerisidir.",style=MaterialTheme.typography.bodySmall)
        TextButton({change(defaults(scope.text("cycle")))},enabled=enabled){Text("Varsayılanlara dön")}
        TextButton(curriculum,enabled=enabled){Text("Firma varsayılanı olarak kaydet")}
        EducationSection("Gerçekleşen günler / saatler") {
            Text("Europe/Istanbul · ${topics.sumOf { it.number("instruction_minutes") }} dk öğretim + ${scope.objects("lessons").sumOf { it.number("break_minutes") }} dk ara")
            val entries=scope.objects("day_entries")
            entries.forEachIndexed { index,day->
                EducationInput("Gün ve başlangıç (2026-09-10 09:00)",day.text("start"),{change(replace(scope,"day_entries",index,day.with("start",it)))},enabled)
                EducationInput("Ders sayısı",day.text("count"),{if(it.toIntOrNull() in 1..24)change(replace(scope,"day_entries",index,day.with("count",it)))},enabled)
                EducationInput("Ek ara (dk, 4. dersten sonra)",day.text("extra"),{if(it.toIntOrNull() in 0..720)change(replace(scope,"day_entries",index,day.with("extra",it)))},enabled)
                TextButton({change(scope.with("day_entries",objects(entries.filterIndexed { n,_->n!=index })))},enabled=enabled){Text("Günü kaldır")}
            }
            TextButton({change(scope.with("day_entries",objects(entries+buildJsonObject { put("start",LocalDateTime.now(EducationRules.zone).minusDays(1).withHour(9).withMinute(0).format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")));put("count","8");put("extra","0") })))},enabled=enabled){Text("Gerçekleşen gün ekle")}
            TextButton({
                runCatching {
                    val days=entries.map { EducationRules.Day(LocalDateTime.parse(it.text("start"),DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")),it.text("count").toInt(),extraMinutes=it.text("extra").toInt()) }
                    require(days.isNotEmpty());change(scope.with("lessons",objects(EducationRules.distribute(topics,days,basic))));error=null
                }.onFailure { error="Gün, saat ve ders sayısını kontrol edin." }
            },enabled=enabled){Text("Konuları derslere dağıt")}
            error?.let { Text(it,color=MaterialTheme.colorScheme.error) }
            scope.objects("lessons").forEachIndexed { index,lesson->
                Text("${lesson.number("instruction_minutes")} dk öğretim")
                EducationDateTime("Ders başlangıcı",lesson.text("starts_at"),enabled){change(replace(scope,"lessons",index,lesson.with("starts_at",it)))}
                EducationInput("Ardından ara (dk)",lesson.number("break_minutes").toString(),{it.toIntOrNull()?.takeIf { n->n in 0..720 }?.let { n->change(replace(scope,"lessons",index,lesson.with("break_minutes",n))) }},enabled)
            }
        }
        EducationSection("Belge bilgileri") {
            EducationInput("İşyeri tam unvanı",scope.text("legal_name"),{change(scope.with("legal_name",it))},enabled)
            EducationInput("Yer / bağlantı açıklaması",scope.text("location"),{change(scope.with("location",it))},enabled)
            EducationInput("İşveren / vekili adı soyadı",scope.text("employer_name"),{change(scope.with("employer_name",it))},enabled)
            EducationChoice("Sıfat",scope.text("employer_capacity"),mapOf("employer" to "İşveren","representative" to "İşveren vekili"),enabled){change(scope.with("employer_capacity",it))}
            if(scope.text("cycle")=="custom")EducationInput("Tekrar aralığı (ay, 0: yok)",scope.number("renewal_months").toString(),{it.toIntOrNull()?.takeIf { n->n in 0..120 }?.let { n->change(scope.with("renewal_months",n)) }},enabled)
        }
        scope.strings("issues").forEach { Text(EducationRules.issue(it),color=MaterialTheme.colorScheme.error) }
        TextButton(remove,enabled=enabled){Text("Kapsamı kaldır")}
    }
}

@Composable private fun EducationDateTime(label: String, value: String, enabled: Boolean, update: (String)->Unit) {
    val context=androidx.compose.ui.platform.LocalContext.current
    val date=runCatching { java.time.Instant.parse(value).atZone(EducationRules.zone) }.getOrElse { java.time.ZonedDateTime.now(EducationRules.zone) }
    OutlinedButton({
        android.app.DatePickerDialog(context,{ _,year,month,day->
            android.app.TimePickerDialog(context,{ _,hour,minute->
                update(java.time.LocalDateTime.of(year,month+1,day,hour,minute).atZone(EducationRules.zone).toInstant().toString())
            },date.hour,date.minute,true).show()
        },date.year,date.monthValue-1,date.dayOfMonth).apply { datePicker.maxDate=System.currentTimeMillis() }.show()
    },enabled=enabled){Text(label+": "+date.format(DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm")))}
}
