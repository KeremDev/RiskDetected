package com.riskdetectedan.core.data.education

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.LocalDateTime

class EducationRulesTest {
    private val content=Json.parseToJsonElement(File("../../../content/education/tr-isg-2026-v1.json").readText()).jsonObject
    @Test fun sixProfilesKeepExactMinutesAndNoAutomaticTrainerAssignment() {
        content.objects("presets").forEach { p->
            val topics=EducationRules.topics(content,p.text("cycle"),p.text("hazard_class"))
            assertEquals(p.number("default_instruction_minutes"),topics.sumOf { it.number("instruction_minutes") })
            assertEquals(p.getValue("group4").jsonObject.number("budget_instruction_minutes"),topics.filter { it.text("group")=="G4" }.sumOf { it.number("instruction_minutes") })
            assertTrue(topics.all { it.strings("trainer_ids").isEmpty() })
        }
    }
    @Test fun surplusMinutesDoNotBecomeAnotherCreditedLesson() {
        val topics=EducationRules.topics(content,"initial","low").toMutableList()
        topics[0]=topics[0].with("instruction_minutes",topics[0].number("instruction_minutes")+10)
        val start=LocalDateTime.of(2026,9,10,9,0)
        val lessons=EducationRules.distribute(topics,listOf(EducationRules.Day(start,8)),true)
        assertEquals(8,lessons.size);assertEquals(55,lessons.last().number("instruction_minutes"))
        assertEquals(370,lessons.sumOf { it.number("instruction_minutes") });assertEquals(120,lessons.sumOf { it.number("break_minutes") })
        assertEquals("2026-09-10T06:00:00Z",lessons.first().text("starts_at"))
        topics.forEach { t->assertEquals(t.number("instruction_minutes"),lessons.flatMap { it.objects("allocations") }.filter { it.text("topic_code")==t.text("code") }.sumOf { it.number("minutes") }) }
    }
    @Test fun extraBreakAndMultipleDaysNeverAddInstructionMinutes() {
        val topics=EducationRules.topics(content,"initial","high")
        val lessons=EducationRules.distribute(topics,listOf(EducationRules.Day(LocalDateTime.of(2026,9,10,9,0),8,4,45),EducationRules.Day(LocalDateTime.of(2026,9,11,9,0),8)),true)
        assertEquals(720,lessons.sumOf { it.number("instruction_minutes") });assertEquals(285,lessons.sumOf { it.number("break_minutes") })
        assertEquals("2026-09-11T06:00:00Z",lessons[8].text("starts_at"))
    }
    @Test fun customTitleCannotTurnIntoOfficialProfile() {
        assertNull(EducationRules.preset(content,"custom","high"))
        assertEquals(120,EducationRules.topics(content,"onboarding","high").sumOf { it.number("instruction_minutes") })
        assertEquals(12,EducationRules.topic("CUSTOM-1","G4","Temel İSG",12).number("instruction_minutes"))
    }
}
