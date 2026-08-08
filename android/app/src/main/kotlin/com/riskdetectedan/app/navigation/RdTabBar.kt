package com.riskdetectedan.app.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdTheme

/** Port of App/Views/Components/RDTabBar.swift — floating translucent capsule with 4 icon-only
 * tabs + a separate circular quick-scan button. iOS's `.ultraThinMaterial` live backdrop blur has
 * no direct Compose equivalent without API 31+ `RenderEffect` plumbing; simplified to a solid
 * translucent surface + shadow (same visual weight, no live blur-through) — documented
 * simplification, not silent. Colors/shadow otherwise match the real onyx/white token pair. */
@Composable
fun RdTabBar(active: RdTab, onTabSelected: (RdTab) -> Unit, onQuickScan: () -> Unit, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp)
            .padding(top = 8.dp, bottom = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .height(52.dp)
                .shadow(elevation = 8.dp, shape = CircleShape)
                .clip(CircleShape)
                .background(colors.white.copy(alpha = 0.92f))
                .border(1.dp, colors.white.copy(alpha = 0.7f), CircleShape)
                .padding(4.dp),
        ) {
            RdTab.entries.forEach { tab ->
                TabButton(tab = tab, isActive = tab == active, onClick = { onTabSelected(tab) }, modifier = Modifier.weight(1f))
            }
        }

        Box(
            modifier = Modifier
                .size(52.dp)
                .shadow(elevation = 8.dp, shape = CircleShape)
                .clip(CircleShape)
                .background(colors.white)
                .border(1.dp, colors.white.copy(alpha = 0.82f), CircleShape)
                .clickable(onClick = onQuickScan)
                .semantics { contentDescription = "Hızlı tarama başlat" },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.CenterFocusStrong, contentDescription = null, tint = colors.green, modifier = Modifier.size(23.dp))
        }
    }
}

@Composable
private fun TabButton(tab: RdTab, isActive: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Box(
        modifier = modifier
            .height(44.dp)
            .clip(CircleShape)
            .background(if (isActive) colors.fog.copy(alpha = 0.9f) else Color.Transparent)
            .clickable(onClick = onClick)
            .semantics { contentDescription = tab.label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            tab.icon,
            contentDescription = null,
            tint = if (isActive) colors.onyx else colors.graphite.copy(alpha = 0.82f),
            modifier = Modifier.size(21.dp),
        )
    }
}
