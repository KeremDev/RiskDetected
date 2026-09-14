package com.riskdetectedan.core.data.education

import kotlinx.serialization.json.*
import java.time.*
import java.util.UUID

fun JsonObject.text(key: String): String = (get(key) as? JsonPrimitive)?.contentOrNull.orEmpty()
fun JsonObject.number(key: String): Int = (get(key) as? JsonPrimitive)?.intOrNull ?: 0
fun JsonObject.flag(key: String): Boolean = (get(key) as? JsonPrimitive)?.booleanOrNull == true
fun JsonObject.objects(key: String): List<JsonObject> = (get(key) as? JsonArray)?.map { it.jsonObject } ?: emptyList()
fun JsonObject.strings(key: String): List<String> = (get(key) as? JsonArray)?.map { it.jsonPrimitive.content } ?: emptyList()
fun JsonObject.with(key: String, value: JsonElement): JsonObject = JsonObject(toMutableMap().apply { put(key,value) })
fun JsonObject.with(key: String, value: String): JsonObject = with(key,JsonPrimitive(value))
fun JsonObject.with(key: String, value: Int): JsonObject = with(key,JsonPrimitive(value))
fun objects(values: List<JsonObject>): JsonArray = JsonArray(values)

object EducationRules {
    val zone: ZoneId = ZoneId.of("Europe/Istanbul")
    val cycles = linkedMapOf("initial" to "İlk Temel Eğitim", "periodic_repeat" to "Tekrar Temel Eğitimi", "onboarding" to "İşe Başlama Eğitimi", "knowledge_refresh" to "Bilgi Yenileme", "additional" to "İlave Eğitim", "workplace_specific" to "Yeni İşyerine Özgü Eğitim", "custom" to "Özel Eğitim")
    fun basic(cycle: String) = cycle in setOf("initial","periodic_repeat")
    fun method(value: String) = when(value) { "online" -> "Online"; "mixed" -> "Karma"; else -> "Yüz yüze" }
    fun preset(content: JsonObject, cycle: String, hazard: String): JsonObject? {
        val normalized = when(hazard) { "high" -> "very_hazardous"; "medium" -> "hazardous"; else -> hazard }
        return content.objects("presets").firstOrNull { it.text("cycle") == cycle && it.text("hazard_class") == normalized }
    }
    fun topics(content: JsonObject, cycle: String, hazard: String): List<JsonObject> {
        val p = preset(content,cycle,hazard) ?: return listOf(topic("CUSTOM-1","G4","Eğitim konusu",if(cycle=="onboarding")120 else 60))
        val minutes = p.getValue("topic_instruction_minutes").jsonObject
        return content.objects("topics").map { topic(it.text("code"),it.text("group_code"),it.text("legal_label"),minutes.number(it.text("code"))) } +
            p.getValue("group4").jsonObject.objects("topics").map { topic(it.text("local_key"),"G4",it.text("title"),it.number("instruction_minutes")) }
    }
    fun topic(code: String, group: String, title: String, minutes: Int) = buildJsonObject {
        put("code",code); put("group",group); put("title",title); put("instruction_minutes",minutes); put("method","face_to_face"); put("trainer_ids",JsonArray(emptyList()))
    }
    fun draft() = buildJsonObject {
        put("action","save"); put("expected_version",0); put("title","Temel İSG Eğitimi"); put("provider_name",""); put("notes","")
        put("trainers",objects(listOf(buildJsonObject { put("id",UUID.randomUUID().toString()); put("name",""); put("title","") })))
        put("scopes",JsonArray(emptyList()))
    }
    fun scope(workplace: JsonObject, content: JsonObject) = buildJsonObject {
        put("id",UUID.randomUUID().toString()); put("company_id",workplace.text("company_id")); put("workplace_id",workplace.text("id"))
        put("company_name",workplace.text("company_name")); put("workplace_name",workplace.text("name")); put("hazard_class",workplace.text("hazard_class"))
        put("group_name","Genel"); put("cycle","initial"); put("context_note",""); put("legal_name",""); put("employer_name",""); put("employer_capacity","representative"); put("location",""); put("renewal_months",0)
        put("topics",objects(topics(content,"initial",workplace.text("hazard_class")))); put("participants",JsonArray(emptyList())); put("lessons",JsonArray(emptyList()))
    }
    data class Day(val starts: LocalDateTime, val count: Int, val extraAfter: Int = 4, val extraMinutes: Int = 0)
    fun distribute(topics: List<JsonObject>, days: List<Day>, basic: Boolean): List<JsonObject> {
        val positive = topics.filter { it.number("instruction_minutes") > 0 }; val total = positive.sumOf { it.number("instruction_minutes") }
        val count = days.sumOf { it.count.coerceAtLeast(0) }; if(total <= 0 || count !in 1..200) return emptyList()
        var topic = 0; var left = positive.first().number("instruction_minutes"); var used = 0; val result = mutableListOf<JsonObject>()
        days.sortedBy { it.starts }.forEach { day ->
            var start = day.starts.atZone(zone)
            repeat(day.count.coerceAtLeast(0)) { local ->
                val amount = if(result.size == count-1)total-used else minOf(if(basic)45 else total/count,total-used)
                if(amount > 0) {
                    var remaining = amount; val allocations = mutableListOf<JsonObject>()
                    while(remaining>0 && topic<positive.size) {
                        val m = minOf(left,remaining); allocations += buildJsonObject { put("topic_code",positive[topic].text("code")); put("minutes",m) }
                        remaining -= m; left -= m; if(left==0) { topic++; if(topic<positive.size)left=positive[topic].number("instruction_minutes") }
                    }
                    val rest = (if(basic)15 else 0) + if(local+1==day.extraAfter)day.extraMinutes else 0
                    result += buildJsonObject { put("id",UUID.randomUUID().toString()); put("starts_at",start.toInstant().toString()); put("instruction_minutes",amount); put("break_minutes",rest); put("allocations",objects(allocations)) }
                    used += amount; start = start.plusMinutes((amount+rest).toLong())
                }
            }
        }
        return result
    }
    fun issue(code: String): String = mapOf(
        "TOPIC_MINUTES_MISSING" to "Konu süresi eksik.", "TRAINER_SCOPE_MISSING" to "Konu eğiticilerini seçin.", "FACE_TO_FACE_REQUIRED" to "İşyerine özgü bölüm yüz yüze olmalı.",
        "REQUIRED_TOPIC_MISSING" to "Zorunlu konu eksik.", "TOTAL_TOO_SHORT" to "Öğretim süresi eksik.", "GROUP4_TOO_SHORT" to "G4 süresi eksik.", "COMMON_GROUPS_TOO_SHORT" to "G1–G3 referans süresi eksik.",
        "GROUP4_CONTEXT_MISSING" to "İşyeri ve görev bağlamını açıklayın.", "LESSON_TOPIC_MISMATCH" to "Konuları ders saatlerine yeniden dağıtın.", "LESSON_BREAK_INVALID" to "Ders en az 45, ara en az 15 dakika olmalı.",
        "EMPLOYER_MISSING" to "İşveren / vekili eksik.", "EMPLOYER_CAPACITY_MISSING" to "İmzalayan sıfatı eksik.", "JOB_TITLE_MISSING" to "Personel unvanı eksik.", "PROVIDER_MISSING" to "Düzenleyici eksik.", "TRAINER_TITLE_MISSING" to "Eğitici unvanı eksik."
    )[code] ?: "Eğitim bilgilerini kontrol edin ($code)."
}
