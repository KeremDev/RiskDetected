package com.riskdetectedan.core.data.error

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure logic, no Android framework dependency — first real JVM unit test in this module (every
 * other repository this session was verified by build+install+emulator screenshot instead, since
 * they all touch Context/Supabase/RevenueCat; this classifier touches neither).
 */
class AppErrorMessageTest {

    @Test
    fun `free risk analysis trial exhausted is classified as quota exceeded`() {
        val result = AppErrorMessages.make("free_risk_analysis_trial_exhausted")
        assertEquals(AppErrorCategory.QuotaExceeded, result.category)
        assertEquals("Risk analizi hakkı kullanıldı", result.title)
    }

    @Test
    fun `report quota exceeded is classified correctly`() {
        val result = AppErrorMessages.make("report_quota_exceeded: aylık rapor kotan doldu")
        assertEquals(AppErrorCategory.QuotaExceeded, result.category)
        assertEquals("Rapor limiti doldu", result.title)
    }

    @Test
    fun `daily quota free tier suggests upgrading`() {
        val result = AppErrorMessages.make("Ücretsiz analiz hakkın için günlük kota doldu")
        assertEquals(AppErrorCategory.QuotaExceeded, result.category)
        assertTrue(result.action.contains("Plus veya Pro"))
    }

    @Test
    fun `daily quota paid tier suggests waiting`() {
        val result = AppErrorMessages.make("günlük detaylı analiz kotan doldu")
        assertEquals(AppErrorCategory.QuotaExceeded, result.category)
        assertTrue(result.action.contains("yenilenene kadar bekle"))
    }

    @Test
    fun `ai rate limit is classified as ai rate limited`() {
        val result = AppErrorMessages.make("429 Too Many Requests from Gemini")
        assertEquals(AppErrorCategory.AiRateLimited, result.category)
    }

    @Test
    fun `ai unavailable 503 is classified as ai unavailable`() {
        val result = AppErrorMessages.make("503 Service Unavailable")
        assertEquals(AppErrorCategory.AiUnavailable, result.category)
    }

    @Test
    fun `auth email hook failure is not misclassified as ai unavailable`() {
        // Real bug caught live (2026-08-09): auth-send-email-hook (OTP/login-code sender)
        // failing surfaces GoTrue's generic wrapper message containing "unavailable" — without
        // this check it fell through to the ai-unavailable branch above and showed a wildly
        // wrong "Analiz modeli şu anda yoğun..." message for a failed login-code send.
        val result = AppErrorMessages.make(
            "500: Service currently unavailable due to hook",
            context = "Kod gönderilemedi",
        )
        assertEquals(AppErrorCategory.Unknown, result.category)
        assertEquals("Kod gönderilemedi", result.title)
        assertTrue(result.message.contains("kod"))
    }

    @Test
    fun `network keyword is classified as network unavailable`() {
        val result = AppErrorMessages.make("network connection lost")
        assertEquals(AppErrorCategory.NetworkUnavailable, result.category)
    }

    @Test
    fun `rls keyword is classified as storage denied`() {
        val result = AppErrorMessages.make("new row violates row-level security policy")
        assertEquals(AppErrorCategory.StorageDenied, result.category)
    }

    @Test
    fun `pdf keyword is classified as pdf render failed`() {
        val result = AppErrorMessages.make("PDF oluşturulamadı: rendering error")
        assertEquals(AppErrorCategory.PdfRenderFailed, result.category)
    }

    @Test
    fun `database keyword is classified as database failed`() {
        val result = AppErrorMessages.make("constraint violation on table profiles")
        assertEquals(AppErrorCategory.DatabaseFailed, result.category)
    }

    @Test
    fun `short unrecognized message is shown verbatim as validation failed`() {
        val result = AppErrorMessages.make("Bu alan boş bırakılamaz")
        assertEquals(AppErrorCategory.ValidationFailed, result.category)
        assertEquals("Bu alan boş bırakılamaz", result.message)
    }

    @Test
    fun `long unrecognized message falls back to generic unknown copy`() {
        val longMessage = "x".repeat(200)
        val result = AppErrorMessages.make(longMessage)
        assertEquals(AppErrorCategory.Unknown, result.category)
        assertEquals("Beklenmeyen bir sorun oluştu ve işlem tamamlanamadı.", result.message)
    }

    @Test
    fun `existing support id in the raw message is reused, not regenerated`() {
        val result = AppErrorMessages.make("Bir hata oluştu. Destek kodu: RD-ABCD1234")
        assertEquals("RD-ABCD1234", result.supportID)
    }

    @Test
    fun `new support id follows the RD- eight char format`() {
        val id = AppErrorMessages.newSupportID()
        assertTrue(Regex("RD-[A-Z0-9]{8}").matches(id))
    }

    @Test
    fun `empty message still gets a fresh support id and unknown category`() {
        val result = AppErrorMessages.make("")
        assertEquals(AppErrorCategory.Unknown, result.category)
        assertTrue(Regex("RD-[A-Z0-9]{8}").matches(result.supportID))
    }
}
