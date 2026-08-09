package com.riskdetectedan.feature.analysis

import com.riskdetectedan.core.data.error.AppErrorMessages
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
}
