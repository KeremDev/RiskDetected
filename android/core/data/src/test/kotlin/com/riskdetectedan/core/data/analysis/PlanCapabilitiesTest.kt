package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.data.profile.SubscriptionTier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanCapabilitiesTest {
    @Test fun productionQuotaMatrixMatchesServerContract() {
        val free = PlanCapabilities.forTier(SubscriptionTier.Free)
        val plus = PlanCapabilities.forTier(SubscriptionTier.Plus)
        val pro = PlanCapabilities.forTier(SubscriptionTier.Pro)
        assertEquals(1, free.standardAnalysisLimit)
        assertNull(free.detailedAnalysisLimit)
        assertEquals(1, free.reportLimit)
        assertEquals(QuotaPeriod.Day, free.reportPeriod)
        assertEquals(1, free.riskAnalysisReportTrialLimit)
        assertEquals(0, free.companyLimit)
        assertEquals(7, free.photoRetentionDays)
        assertEquals(1, free.maxPhotosPerAnalysis)
        assertEquals(1, free.visiblePhotoSlotsInUI)
        assertEquals(12, free.maxFindingsPerPhoto)
        assertEquals(12, free.maxFindingsPerAnalysis)
        assertFalse(free.canUseDetailedAnalysis)
        assertFalse(free.canUseMultiPhotoAnalysis)
        assertFalse(free.canEditAIFindings)
        assertFalse(free.canAddManualFindings)
        assertEquals(10, plus.standardAnalysisLimit)
        assertEquals(2, plus.detailedAnalysisLimit)
        assertEquals(150, plus.reportLimit)
        assertEquals(QuotaPeriod.Month, plus.reportPeriod)
        assertNull(plus.riskAnalysisReportTrialLimit)
        assertEquals(5, plus.companyLimit)
        assertEquals(30, plus.photoRetentionDays)
        assertTrue(plus.canUseDetailedAnalysis)
        assertEquals(3, plus.maxPhotosPerAnalysis)
        assertEquals(3, plus.visiblePhotoSlotsInUI)
        assertEquals(13, plus.maxFindingsPerPhoto)
        assertEquals(39, plus.maxFindingsPerAnalysis)
        assertTrue(plus.canUseMultiPhotoAnalysis)
        assertFalse(plus.canEditAIFindings)
        assertEquals(40, pro.standardAnalysisLimit)
        assertEquals(10, pro.detailedAnalysisLimit)
        assertEquals(750, pro.reportLimit)
        assertEquals(QuotaPeriod.Month, pro.reportPeriod)
        assertEquals(25, pro.companyLimit)
        assertNull(pro.photoRetentionDays)
        assertTrue(pro.canUseDetailedAnalysis)
        assertEquals(3, pro.maxPhotosPerAnalysis)
        assertEquals(3, pro.visiblePhotoSlotsInUI)
        assertEquals(13, pro.maxFindingsPerPhoto)
        assertEquals(39, pro.maxFindingsPerAnalysis)
        assertTrue(pro.canUseMultiPhotoAnalysis)
        assertFalse(pro.canEditAIFindings)
        assertFalse(plus.canAddManualFindings)
        assertFalse(pro.canAddManualFindings)
    }

    @Test fun androidGateNeverUsesGlobalAllMode() {
        assertFalse(AndroidBuildGate.isOpen(false, "all", emptyList(), null, 81))
    }

    @Test fun androidGateSupportsOwnAllowlistAndMinimum() {
        assertTrue(AndroidBuildGate.isOpen(false, "build_allowlist", listOf("1"), null, 1))
        assertTrue(AndroidBuildGate.isOpen(false, "build_allowlist", emptyList(), 10, 10))
        assertFalse(AndroidBuildGate.isOpen(true, "build_allowlist", listOf("1"), null, 1))
    }
}
