package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.NovaExpertFailure
import org.junit.Assert.assertEquals
import org.junit.Test

class NovaModuleEditorServiceTest {
    @Test fun serverRefusalsUseTheIosWords() {
        assertEquals("Kayıt değişmiş. Kapatıp yeniden açarak güncel bilgilerle deneyin.",
            NovaModuleEditorService.message(NovaExpertFailure("VERSION_CONFLICT", "P0001")))
        assertEquals("Bu plana bağlı tatbikat var. Önce bağlı tatbikatı kaldırın.",
            NovaModuleEditorService.message(NovaExpertFailure("DEPENDENT_RECORDS", "P0001")))
        assertEquals("Firma, personel, işyeri veya evrak bu kayda uygun değil.",
            NovaModuleEditorService.message(NovaExpertFailure("ACCESS_DENIED", "P0001")))
        assertEquals("Bilgileri kontrol edin. Kayıt güncellenemedi.",
            NovaModuleEditorService.message(NovaExpertFailure("VALIDATION_ERROR", "23514")))
    }

    @Test fun transportFailuresReadAsConnectionProblems() {
        assertEquals("İşlem tamamlanamadı. Bağlantınızı kontrol edip yeniden deneyin.",
            NovaModuleEditorService.message(NovaExpertFailure("UNAVAILABLE")))
        assertEquals("İşlem tamamlanamadı. Bağlantınızı kontrol edip yeniden deneyin.",
            NovaModuleEditorService.message(IllegalStateException("offline")))
    }
}
