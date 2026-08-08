package com.riskdetectedan.app.home

import androidx.lifecycle.ViewModel
import com.riskdetectedan.core.data.analysis.InFlightAnalysisStore
import com.riskdetectedan.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * Real port of `resumeInFlightAnalysisIfNeeded`'s trigger point (Home's `onAppear`/`.task`) —
 * a lightweight existence check only, deliberately *not* the same ViewModel that does the actual
 * resume work (`AnalysisViewModel.resumeIfInFlight`, scoped to the Analysis screen it navigates
 * into) — Home just needs to know whether to navigate there at all.
 */
@HiltViewModel
class InFlightResumeViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val inFlightStore: InFlightAnalysisStore,
) : ViewModel() {

    /** Non-destructive check (doesn't clear/consume the record — `AnalysisViewModel.resumeIfInFlight`
     * does that once it actually starts polling) — safe to call every time Home recomposes. */
    fun hasInFlightAnalysis(): Boolean {
        val userId = authRepository.currentUserId ?: return false
        return inFlightStore.load(userId) != null
    }
}
