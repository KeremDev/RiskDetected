package com.riskdetectedan.app.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.backgroundColor
import com.riskdetectedan.core.designsystem.color
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Real port of `RecentAnalysisCard.swift` — angular-gradient risk ring (critical/high/medium
 * sweep, via [Brush.sweepGradient]) around a photo circle, bottom-trailing capsule badge
 * (warning-triangle icon + finding count). Simplified, documented: no real photo inside the ring
 * — [HistoryItem] carries no Storage path/signed-URL (no photo-thumbnail-fetch system exists on
 * Android yet, same gap noted since the Faz M-S plan closed) — a risk-level-tinted icon fills the
 * circle instead of the real site photo.
 */
@Composable
fun RecentAnalysisRingCard(item: HistoryItem, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(item.riskBand)
    val ringSize = 94.dp
    val innerSize = 78.dp

    Box(modifier = Modifier.size(ringSize + 8.dp), contentAlignment = Alignment.Center) {
        Box(
            modifier = Modifier
                .size(ringSize)
                .shadow(elevation = 6.dp, shape = CircleShape, ambientColor = Color.Black.copy(alpha = 0.10f), spotColor = Color.Black.copy(alpha = 0.10f))
                .clip(CircleShape)
                .border(
                    3.5.dp,
                    Brush.sweepGradient(
                        listOf(
                            colors.critical.copy(alpha = 0.72f),
                            colors.high.copy(alpha = 0.58f),
                            colors.medium.copy(alpha = 0.52f),
                            colors.critical.copy(alpha = 0.62f),
                            colors.critical.copy(alpha = 0.72f),
                        ),
                    ),
                    CircleShape,
                )
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier.size(innerSize).clip(CircleShape).background(level.backgroundColor()),
                contentAlignment = Alignment.Center,
            ) {
                Text(item.title.take(2).uppercase(), style = RdFontStyle.Callout.toTextStyle(), color = level.color())
            }
        }
        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(3.dp)
                .clip(RoundedCornerShape(50))
                .background(colors.white.copy(alpha = 0.96f))
                .border(1.dp, colors.white.copy(alpha = 0.74f), RoundedCornerShape(50))
                .padding(horizontal = 7.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Warning, contentDescription = null, tint = colors.black, modifier = Modifier.size(9.dp))
            Text(" ${item.findingCount}", style = RdFontStyle.Data.toTextStyle(), color = colors.black)
        }
    }
}
