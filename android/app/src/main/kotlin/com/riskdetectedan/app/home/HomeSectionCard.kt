package com.riskdetectedan.app.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/** Real port of `HomeView.swift`'s `homeSectionCard`/`sectionHeader` — icon chip (tinted 10%
 * background) + title + count label, trailing green "Tümü ›" pill. Shared by
 * the recent-analyses/generated-reports sections in [HomeScreen]. */
@Composable
fun HomeSectionCard(
    title: String,
    icon: ImageVector,
    tint: Color,
    countLabel: String,
    onSeeAll: () -> Unit,
    content: @Composable () -> Unit,
) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(RdRadius.lg))
            .padding(RdSpacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(28.dp).clip(RoundedCornerShape(RdRadius.sm)).background(tint.copy(alpha = 0.10f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(14.dp))
            }
            Spacer(Modifier.width(RdSpacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
                Text(countLabel, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate.copy(alpha = 0.82f))
            }
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(colors.greenSoft.copy(alpha = 0.72f))
                    .clickable(onClick = onSeeAll)
                    .padding(horizontal = RdSpacing.sm)
                    .height(28.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Tümü", style = RdFontStyle.Caption.toTextStyle(), color = colors.greenDark)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(14.dp))
            }
        }
        Spacer(Modifier.height(RdSpacing.sm))
        content()
    }
}
