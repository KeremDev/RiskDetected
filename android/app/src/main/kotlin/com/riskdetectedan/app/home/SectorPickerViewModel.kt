package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisSectorPickerItem
import com.riskdetectedan.core.data.analysis.AnalysisSectorPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/** Thin Hilt wrapper around [AnalysisSectorPreferences] — Composables can't inject a plain
 * singleton directly, this is the same "one small ViewModel per concern" shape as every other
 * Home-adjacent ViewModel in this screen (`QuotaViewModel`, `HomeTierViewModel`, etc.). No
 * StateFlow needed — [pickerItems] is a cheap synchronous SharedPreferences read, recomputed
 * fresh each time the sheet opens rather than cached/observed. */
@HiltViewModel
class SectorPickerViewModel @Inject constructor(
    private val sectorPreferences: AnalysisSectorPreferences,
) : ViewModel() {
    fun pickerItems(): List<AnalysisSectorPickerItem> = sectorPreferences.pickerItems()

    fun recordLastUsed(sector: AnalysisSector) = sectorPreferences.recordLastUsed(sector)
}
