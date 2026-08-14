package com.riskdetectedan.app.home

import org.junit.Assert.assertEquals
import org.junit.Test

class QuickScanReducerTest {
    @Test fun exhaustedFreeUserSeesUpgradeBeforeAnyPicker() {
        assertEquals(
            QuickScanDecision.Upgrade,
            QuickScanReducer.decide(isPaid = false, quotaExhausted = true, hasPhotos = false),
        )
    }

    @Test fun emptyDraftOpensCameraGalleryTray() {
        assertEquals(
            QuickScanDecision.OpenPhotoTray,
            QuickScanReducer.decide(isPaid = false, quotaExhausted = false, hasPhotos = false),
        )
    }

    @Test fun existingDraftContinuesWithSectorSelection() {
        assertEquals(
            QuickScanDecision.SelectSector,
            QuickScanReducer.decide(isPaid = true, quotaExhausted = false, hasPhotos = true),
        )
    }
}
