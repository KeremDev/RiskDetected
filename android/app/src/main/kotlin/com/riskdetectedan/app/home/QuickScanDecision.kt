package com.riskdetectedan.app.home

internal enum class QuickScanDecision {
    Upgrade,
    OpenPhotoTray,
    SelectSector,
}

/** Pure contract for live iOS MainTabView -> Home quick-scan ordering. */
internal object QuickScanReducer {
    fun decide(
        isPaid: Boolean,
        quotaExhausted: Boolean,
        hasPhotos: Boolean,
    ): QuickScanDecision = when {
        !isPaid && quotaExhausted -> QuickScanDecision.Upgrade
        !hasPhotos -> QuickScanDecision.OpenPhotoTray
        else -> QuickScanDecision.SelectSector
    }
}
