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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

private val CardCorner = RoundedCornerShape(16.dp)

/** Shared soft card-depth shadow approximating `RDDepthShadowModifier`'s stacked
 * black/slate/accent shadows (a single native `Modifier.shadow` layer here — Compose has no
 * built-in multi-shadow stacking — tuned to read close to the same softness/weight). Used by
 * every Home card so the whole screen reads as "elevated" like iOS instead of flat bordered
 * boxes. */
fun Modifier.rdHomeCardShadow(shape: androidx.compose.ui.graphics.Shape = CardCorner): Modifier = this.shadow(
    elevation = 10.dp,
    shape = shape,
    ambientColor = Color.Black.copy(alpha = 0.10f),
    spotColor = Color.Black.copy(alpha = 0.16f),
)

/** Real port of `HomeView.swift`'s `homeSectionCard`/`sectionHeader` — icon chip (tinted 10%
 * background) + title + count label, trailing green "Tümü ›" pill, real card-depth shadow
 * (`homeCardDepth`). Shared by the recent-analyses/generated-reports sections in [HomeScreen] —
 * both are now unconditionally rendered (matching iOS's own always-visible `recentSection`/
 * `generatedReportsSection`, which show a real empty-state row via [EmptyHomeSectionRow] instead
 * of disappearing when there's no data — the previous pass incorrectly hid the whole section). */
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
            .rdHomeCardShadow(CardCorner)
            .clip(CardCorner)
            .background(colors.white)
            .border(1.dp, colors.line, CardCorner)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(28.dp).clip(RoundedCornerShape(9.dp)).background(tint.copy(alpha = 0.10f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(13.dp))
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

/** Real port of `emptyRecentCard`/`emptyReportsCard` — 42x42 tinted icon chip + title/subtitle,
 * shown inside [HomeSectionCard] whenever there's nothing to list yet, matching iOS's real
 * always-visible section behavior. */
@Composable
fun EmptyHomeSectionRow(icon: ImageVector, iconTint: Color, iconBackground: Color, title: String, subtitle: String) {
    val colors = RdTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier.size(42.dp).clip(RoundedCornerShape(12.dp)).background(iconBackground),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(RdSpacing.sm))
        Column {
            Text(title, style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
            Text(subtitle, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
        }
    }
}
