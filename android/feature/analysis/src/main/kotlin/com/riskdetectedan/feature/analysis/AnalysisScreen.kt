package com.riskdetectedan.feature.analysis

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Sector picker + "create analysis" — proves the `analyses` insert path (RLS as the
 * authenticated user) end to end. Photo capture/upload and the actual `analyze` call (the rest
 * of App/Services/AnalysisService.swift's submit flow) are separate, larger, not built yet.
 */
@Composable
fun AnalysisScreen(photoPath: String? = null, viewModel: AnalysisViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    var selectedSector by remember { mutableStateOf<AnalysisSector?>(null) }

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        if (photoPath != null) {
            Text("Fotoğraf hazır — sektör seçince yüklenecek")
        }
        Text("Sektör seç")
        LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
            items(AnalysisSector.entries) { sector ->
                val isSelected = selectedSector == sector
                ListItem(
                    headlineContent = {
                        Text(if (isSelected) "✓ ${sector.titleTr}" else sector.titleTr)
                    },
                    modifier = Modifier.clickable {
                        selectedSector = sector
                        viewModel.createAnalysis(sector, photoPath)
                    },
                )
            }
        }

        when (val current = state) {
            is CreateAnalysisUiState.Idle -> Unit
            is CreateAnalysisUiState.Creating -> CircularProgressIndicator()
            is CreateAnalysisUiState.UploadingPhoto -> CircularProgressIndicator()
            is CreateAnalysisUiState.Created -> Text(
                if (current.photoUploaded) {
                    "Analiz + fotoğraf yüklendi: ${current.analysisId}"
                } else {
                    "Analiz oluşturuldu (fotoğrafsız): ${current.analysisId}"
                },
            )
            is CreateAnalysisUiState.Failed ->
                Text("Analiz oluşturulamadı: ${current.message}")
        }
    }
}
