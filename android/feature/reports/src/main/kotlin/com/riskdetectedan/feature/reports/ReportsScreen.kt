package com.riskdetectedan.feature.reports

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.backgroundColor
import com.riskdetectedan.core.designsystem.color
import com.riskdetectedan.core.designsystem.riskLevelFromRaw

/** Port of the analysis history list (App/Models/HistoryItem.swift's `init(row:)` mapping —
 * not a port of App/Views/History/HistoryView.swift's layout, which wasn't read; this reuses
 * the same functional-list pattern as every other screen built this session). */
@Composable
fun ReportsScreen(viewModel: HistoryViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Geçmiş analizler")
        when (val current = state) {
            is HistoryUiState.Loading -> CircularProgressIndicator()
            is HistoryUiState.SignedOut -> Text("Oturum yok")
            is HistoryUiState.Failed -> Text("Geçmiş yüklenemedi: ${current.message}")
            is HistoryUiState.Loaded -> {
                if (current.items.isEmpty()) {
                    Text("Henüz analiz yok")
                } else {
                    LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
                        items(current.items) { item -> HistoryRow(item) }
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(item: HistoryItem) {
    val level = riskLevelFromRaw(item.riskBand)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = RdSpacing.xs),
    ) {
        Text(
            text = level.name,
            modifier = Modifier
                .background(level.backgroundColor(), RoundedCornerShape(RdRadius.xs))
                .padding(horizontal = RdSpacing.xs, vertical = RdSpacing.xxs),
            color = level.color(),
        )
        Column(modifier = Modifier.padding(start = RdSpacing.sm)) {
            Text(item.title)
            Text("${item.findingCount} bulgu · ${item.historyStatus}")
        }
    }
}
