package com.riskdetectedan.feature.onboarding.nova

import com.riskdetectedan.core.data.onboarding.OnboardingAnswerChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NovaOnboardingModelTest {
    @Test
    fun draftCarriesTheNovaVersionAndCatalogueLabels() {
        val draft = NovaOBAnswers(cert = "B", role = "uzman", sectors = listOf("insaat", "gida"), inspections = 3).makeDraft()
        assertEquals("nova-v1", draft.onboardingVersion)
        assertEquals(OnboardingAnswerChoice("B", "B Sınıfı"), draft.certificateClass)
        assertEquals(OnboardingAnswerChoice("uzman", "İş Güvenliği Uzmanı"), draft.professionalRole)
        assertEquals(listOf(OnboardingAnswerChoice("insaat", "İnşaat"), OnboardingAnswerChoice("gida", "Gıda")), draft.sectors)
        assertEquals(OnboardingAnswerChoice("inspections_3", "3 teftiş"), draft.auditFrequency)
        assertNull(draft.safetyProfileId)
        assertEquals(emptyList<OnboardingAnswerChoice>(), draft.hazardClasses)
    }

    @Test
    fun freeTextReplacesTheOtherLabelOnlyWhenWritten() {
        val written = NovaOBAnswers(role = "diger", roleOther = " Saha şefi ", sectors = listOf("diger"), sectorsOther = "Denizcilik").makeDraft()
        assertEquals(OnboardingAnswerChoice("diger", "Saha şefi"), written.professionalRole)
        assertEquals(listOf(OnboardingAnswerChoice("diger", "Denizcilik")), written.sectors)

        val blank = NovaOBAnswers(role = "diger", sectors = listOf("diger")).makeDraft()
        assertEquals(OnboardingAnswerChoice("diger", "Diğer"), blank.professionalRole)
        assertEquals(listOf(OnboardingAnswerChoice("diger", "Diğer")), blank.sectors)
    }

    @Test
    fun zeroInspectionsIsAnAnswerNotAGap() {
        assertEquals(OnboardingAnswerChoice("inspections_0", "Teftiş deneyimi yok"), NovaOBAnswers().makeDraft().auditFrequency)
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
