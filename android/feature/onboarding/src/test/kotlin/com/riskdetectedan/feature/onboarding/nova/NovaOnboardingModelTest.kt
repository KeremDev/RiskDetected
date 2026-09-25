package com.riskdetectedan.feature.onboarding.nova

import com.riskdetectedan.core.data.onboarding.OnboardingAnswerChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NovaOnboardingModelTest {
    @Test
    fun draftMapsTheFittingAnswersOntoTheServerColumns() {
        val draft = NovaOBAnswers(cert = "B", role = "uzman", sectors = listOf("insaat", "gida", "tekstil", "metal"), inspections = 3).makeDraft()
        // upsert_onboarding_v2_answers takes only "v2" and checks every column against its lists.
        assertEquals("v2", draft.onboardingVersion)
        assertEquals(OnboardingAnswerChoice("B", "B Sınıfı"), draft.certificateClass)
        assertEquals(OnboardingAnswerChoice("uzman", "İş Güvenliği Uzmanı"), draft.professionalRole)
        assertEquals(listOf("construction", "food_production", "manufacturing"), draft.sectors.map { it.value })
        assertEquals(OnboardingAnswerChoice("2-5", "3 teftiş"), draft.auditFrequency)
        assertNull(draft.safetyProfileId)
        assertEquals(emptyList<OnboardingAnswerChoice>(), draft.hazardClasses)
        assertEquals("nova-v1", draft.nova?.flow)
    }

    @Test
    fun novaKeepsEveryAnswer() {
        val answers = NovaOBAnswers(
            name = " Kerem ", cert = "none", work = "osgb", role = "diger", roleOther = "Saha şefi", exp = 1,
            sectors = listOf("maden", "diger"), sectorsOther = "Denizcilik", trainings = listOf("nebosh", "diger"),
            trainingsOther = "ISO 45001", approach = listOf("iletisim", "mevzuat"), inspections = 20,
            growth = listOf("risk", "diger"), growthOther = "Ergonomi", assist = listOf("risk", "kontrol"),
        )
        val nova = requireNotNull(answers.makeDraft(skipped = setOf("growth", "approach"), marketing = true).nova)
        assertEquals("Kerem", nova.name)
        assertEquals(OnboardingAnswerChoice("none", "Henüz sertifikam yok"), nova.certificate)
        assertEquals(OnboardingAnswerChoice("osgb", "OSGB"), nova.work)
        assertEquals(OnboardingAnswerChoice("diger", "Saha şefi"), nova.role)
        assertEquals(OnboardingAnswerChoice("3-7", "3–7 yıl"), nova.experience)
        assertEquals(listOf(OnboardingAnswerChoice("maden", "Maden"), OnboardingAnswerChoice("diger", "Denizcilik")), nova.sectors)
        assertEquals(listOf(OnboardingAnswerChoice("nebosh", "NEBOSH"), OnboardingAnswerChoice("diger", "ISO 45001")), nova.trainings)
        assertEquals(listOf("iletisim", "mevzuat"), nova.approach.map { it.value })
        assertEquals(20, nova.inspections)
        assertEquals(OnboardingAnswerChoice("diger", "Ergonomi"), nova.growth.last())
        assertEquals(listOf("risk", "kontrol"), nova.assist.map { it.value })
        assertEquals(listOf("approach", "growth"), nova.skipped)
        assertEquals(true, nova.marketingEmailOptIn)
    }

    @Test
    fun answersOutsideTheServerListsStayOnlyInNova() {
        val draft = NovaOBAnswers(cert = "none", expLess = true, sectors = listOf("diger"), sectorsOther = "Denizcilik").makeDraft()
        assertNull("no certificate is no column value", draft.certificateClass)
        assertNull("no inspection is no column value", draft.auditFrequency)
        assertEquals(listOf(OnboardingAnswerChoice("other", "Denizcilik")), draft.sectors)
        assertEquals(OnboardingAnswerChoice("0-1", "1 yıldan az"), draft.nova?.experience)
        assertNull("marketing was not asked", draft.nova?.marketingEmailOptIn)
        assertEquals(true, draft.hasProfileAnswers)
    }

    @Test
    fun everyNovaAnswerFitsTheServerChecks() {
        // The CHECK lists of public.user_onboarding_answers (staging, 2026-09-25).
        val serverSectors = setOf(
            "construction", "manufacturing", "energy", "mining", "office", "other", "logistics_warehouse",
            "chemical_laboratory", "healthcare", "food_production", "agriculture_livestock", "retail",
            "municipal_field_services", "education", "hospitality",
        )
        val sectorOptions = requireNotNull(NovaOBCatalogue.question("sectors")).options.map { it.value }
        assertEquals(sectorOptions.toSet(), NovaOBAnswers.SERVER_SECTORS.keys)
        assertEquals(true, serverSectors.containsAll(NovaOBAnswers.SERVER_SECTORS.values))
        for (cert in requireNotNull(NovaOBCatalogue.question("cert")).options.map { it.value }) {
            val value = NovaOBAnswers(cert = cert).makeDraft().certificateClass?.value
            assertEquals(true, value == null || value in setOf("A", "B", "C", "doctor", "otherHealth"))
        }
        for (count in 0..40) {
            val value = NovaOBAnswers(inspections = count).makeDraft().auditFrequency?.value
            assertEquals(true, value == null || value in setOf("1", "2-5", "6-15", "15+"))
        }
    }

    @Test
    fun catalogueMatchesThePrototype() {
        assertEquals(listOf("name", "cert", "work", "role", "exp", "sectors", "trainings", "approach", "inspections", "growth", "assist"),
            NovaOBCatalogue.questions.map { it.id })
        assertEquals(2, NovaOBCatalogue.question("approach")?.max)
        assertEquals("yok", NovaOBCatalogue.question("growth")?.exclusive)
    }

    @Test
    fun emailCheckMatchesIos() {
        assertEquals(true, NovaOBAuth.isValidEmail(" uzman@firma.com.tr "))
        listOf("", "@firma.com", "uzman@", "uzman@firma", "uzman@.com", "uzman@firma.", "uz man@firma.com", "a@b@c.com")
            .forEach { assertEquals(it, false, NovaOBAuth.isValidEmail(it)) }
    }
}
