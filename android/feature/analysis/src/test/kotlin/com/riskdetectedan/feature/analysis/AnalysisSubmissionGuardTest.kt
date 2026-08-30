package com.riskdetectedan.feature.analysis

import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.analysis.AnalysisStatus
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnalysisSubmissionGuardTest {
    @Test
    fun `double tap cannot start a second analysis while submission is active`() {
        assertFalse(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.Creating))
        assertFalse(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.UploadingPhoto))
        assertFalse(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.Submitting))
        assertFalse(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.Polling("analysis-id")))
        assertFalse(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.Finalizing("analysis-id")))
        assertFalse(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.LoadingCompletedResult("analysis-id")))
        assertFalse(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.Completed("analysis-id", emptyList())))
    }

    @Test
    fun `explicit retry states may start again`() {
        assertTrue(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.Idle))
        assertTrue(AnalysisSubmissionGuard.canStart(CreateAnalysisUiState.CreatedWithoutPhoto("analysis-id")))
        assertTrue(
            AnalysisSubmissionGuard.canStart(
                CreateAnalysisUiState.Failed(AppErrorMessages.make("Tekrar denenebilir")),
            ),
        )
    }

    @Test fun `only terminal server statuses clear process death recovery record`() {
        assertTrue(AnalysisRecoveryPolicy.shouldClearInFlight(AnalysisStatus.Completed))
        assertTrue(AnalysisRecoveryPolicy.shouldClearInFlight(AnalysisStatus.Failed("failed")))
        assertFalse(AnalysisRecoveryPolicy.shouldClearInFlight(AnalysisStatus.TimedOut))
        assertFalse(AnalysisRecoveryPolicy.shouldClearInFlight(AnalysisStatus.InProgress("processing")))
    }

    @Test fun `submit network failure recovers only after readable non pending status`() {
        assertFalse(AnalysisRecoveryPolicy.serverAcceptedSubmission(RdResult.Success("pending")))
        assertTrue(AnalysisRecoveryPolicy.serverAcceptedSubmission(RdResult.Success("processing")))
        assertTrue(AnalysisRecoveryPolicy.serverAcceptedSubmission(RdResult.Success("completed")))
        assertFalse(AnalysisRecoveryPolicy.serverAcceptedSubmission(RdResult.Failure("network", "offline")))
    }
}
