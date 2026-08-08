package com.riskdetectedan.app.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.HealthAndSafety
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdRiskChip
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.feature.reports.HistoryUiState
import com.riskdetectedan.feature.reports.HistoryViewModel

/**
 * Not a port of App/Views/Home/HomeView.swift's layout (2852 lines — full stats/widget/timeline
 * dashboard) or `MainTabView.swift`'s 4-tab bar — a real, honest visual pass over Android's actual
 * 3-destination hub (Capture/History/Profile), reusing the just-built [RdListRow]/[RdSectionCard]/
 * [RdRiskChip] core-flow components (Faz F). iOS's "reports" tab (generated PDF/XLSX list) still
 * doesn't exist here separately (pre-existing scope note, not new) — only the analyses/history
 * list this app calls "Reports".
 *
 * Reuses `feature:reports`'s already-built [HistoryViewModel] for the last-analysis summary card
 * (rather than adding a second parallel query) — `app` already depends on `feature:reports` for
 * `ReportsScreen`, so this doesn't add a new module edge.
 */
@Composable
fun HomeScreen(
    onCapture: () -> Unit = {},
    onHistory: () -> Unit = {},
    onProfile: () -> Unit = {},
    viewModel: HistoryViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.paper)
            .padding(horizontal = RdSpacing.lg),
    ) {
        Spacer(Modifier.height(RdSpacing.xl))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(44.dp).clip(CircleShape).background(colors.onyx),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.HealthAndSafety, contentDescription = null, tint = colors.white, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(RdSpacing.sm))
            Column {
                Text("RiskDetected", style = RdFontStyle.Title2.toTextStyle(), color = colors.onyx)
                Text("Profesyonel İSG Asistanı", style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
            }
        }

        Spacer(Modifier.height(RdSpacing.xl))
        Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
            RdListRow(
                title = "Fotoğraf çek",
                subtitle = "Yeni analiz başlat",
                icon = Icons.Filled.CameraAlt,
                iconTint = colors.white,
                iconBackground = colors.onyx,
                onClick = onCapture,
            )
            RdListRow(
                title = "Geçmiş analizler",
                subtitle = "Tüm analizlerini gör",
                icon = Icons.Filled.History,
                onClick = onHistory,
            )
            RdListRow(
                title = "Profil",
                subtitle = "Hesap ve ayarlar",
                icon = Icons.Filled.Person,
                onClick = onProfile,
            )
        }

        val loaded = state as? HistoryUiState.Loaded
        val lastItem = loaded?.items?.firstOrNull()
        if (state is HistoryUiState.Loading) {
            Spacer(Modifier.height(RdSpacing.xl))
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
        } else if (lastItem != null) {
            Spacer(Modifier.height(RdSpacing.xl))
            RdSectionCard(title = "Son Analiz") {
                LastAnalysisRow(item = lastItem, onClick = onHistory)
            }
        }
    }
}

@Composable
private fun LastAnalysisRow(item: HistoryItem, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(item.riskBand)
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(item.title, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx)
            Text(
                "${item.findingCount} bulgu · ${item.createdAt?.take(10) ?: ""}",
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
            )
        }
        RdRiskChip(level = level)
    }
}
