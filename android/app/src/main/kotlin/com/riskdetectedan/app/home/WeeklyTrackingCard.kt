package com.riskdetectedan.app.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Port of `ProfessionalProgressWeeklyTrackingCard.swift`'s `.compact` style — the lavender/green
 * card at the very top of Home (above `photoUploadCard`). Real data via
 * [ProfessionalProgressSummary.weeklyTracking] (the actual message-generation logic, not the raw
 * row). Simplified: iOS's two-layer icon (gradient circle + sparkle badge for the no-activity
 * state, or a checkmark-seal for the has-activity state) reduced to one icon in a tinted circle —
 * same "structure real, decoration simplified" pattern as everywhere else in this feature.
 */
@Composable
fun WeeklyTrackingCard(summary: ProfessionalProgressSummary) {
    val colors = RdTheme.colors
    val tracking = summary.weeklyTracking
    val hasActivity = tracking.hasActivity
    val iconTint = if (hasActivity) colors.greenDark else colors.info
    val iconBg = if (hasActivity) colors.green.copy(alpha = 0.14f) else colors.info.copy(alpha = 0.13f)
    val borderColor = if (hasActivity) colors.green.copy(alpha = 0.18f) else colors.info.copy(alpha = 0.18f)
    val gradient = if (hasActivity) {
        Brush.linearGradient(listOf(colors.greenSoft.copy(alpha = 0.86f), colors.white))
    } else {
        Brush.linearGradient(listOf(colors.info.copy(alpha = 0.10f), colors.white))
    }

    val shape = RoundedCornerShape(RdRadius.lg)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .rdHomeCardShadow(shape)
            .clip(shape)
            .background(gradient)
            .border(1.dp, borderColor, shape)
            .padding(horizontal = RdSpacing.md, vertical = RdSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(34.dp).clip(RoundedCornerShape(RdRadius.md)).background(iconBg),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (hasActivity) Icons.Filled.CheckCircle else Icons.Filled.PlayArrow,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(18.dp),
            )
        }
        Spacer(Modifier.width(RdSpacing.sm))
        Text(
            tracking.body,
            style = RdFontStyle.Callout.toTextStyle(),
            color = colors.black,
            maxLines = 2,
        )
    }
}
