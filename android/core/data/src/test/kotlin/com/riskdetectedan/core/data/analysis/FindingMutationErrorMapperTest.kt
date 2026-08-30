package com.riskdetectedan.core.data.analysis

import org.junit.Assert.assertEquals
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.util.Locale

class FindingMutationErrorMapperTest {
    private lateinit var originalLocale: Locale

    @Before
    fun useTurkishLocale() {
        originalLocale = Locale.getDefault()
        Locale.setDefault(Locale.forLanguageTag("tr-TR"))
    }

    @After
    fun restoreLocale() {
        Locale.setDefault(originalLocale)
    }
    @Test
    fun `decodes edge function error and keeps support id`() {
        val failure = FindingMutationErrorMapper.decode(
            body = """{"error":"editable_findings_disabled","message":"Bulgu düzenleme geçici olarak kapalı.","support_id":"RD-1234"}""",
            fallbackCode = "finding_update_failed",
            fallbackMessage = "Bulgu güncellenemedi.",
        )

        assertEquals("editable_findings_disabled", failure.code)
        assertEquals("Bulgu düzenleme geçici olarak kapalı. Destek kodu: RD-1234", failure.message)
    }

    @Test
    fun `uses safe fallback for malformed response`() {
        val failure = FindingMutationErrorMapper.decode(
            body = "not-json",
            fallbackCode = "finding_delete_failed",
            fallbackMessage = "Bulgu silinemedi.",
        )

        assertEquals("finding_delete_failed", failure.code)
        assertEquals("Bulgu silinemedi.", failure.message)
    }
}
