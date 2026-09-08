package com.riskdetectedan.app.telemetry

import androidx.lifecycle.ViewModel
import com.riskdetectedan.core.data.telemetry.ClientFlowEvents
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

@HiltViewModel
class FlowDiagnosticsViewModel @Inject constructor(private val events: ClientFlowEvents) : ViewModel() {
    fun record(stage: String, outcome: String, reason: String) = events.record(stage, outcome, reason)
}
