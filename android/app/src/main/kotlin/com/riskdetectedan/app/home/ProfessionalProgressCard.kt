package com.riskdetectedan.app.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.data.progress.ProfessionalProgressTitle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Faz S — port of `ProfessionalProgressHomeCard.swift`/`ProfessionalProgressWeeklyTrackingCard.swift`
 * in scope (real data, real tap-to-open-titles-sheet interaction), consolidated into one card
 * rather than iOS's two separately-positioned cards (weekly tracking above the scan action, home
 * card below it) — Android's Home doesn't have the same two-anchor-point layout those cards sit
 * between, so one combined card (title/MDP/progress toward next title, weekly summary line when
 * present) reads better here. Real simplification, documented — not a silent visual drop like the
 * per-title accent colors (see [ProfessionalProgressTitle]'s own doc comment, from Faz #24).
 */
@Composable
fun ProfessionalProgressCard(progress: ProfessionalProgressSummary, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .clickable(onClick = onClick)
            .padding(RdSpacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.EmojiEvents, contentDescription = null, tint = colors.onyx, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(RdSpacing.xs))
            Text(
                "${progress.currentTitle.label} · ${progress.profile.totalMdp} MDP",
                style = RdFontStyle.Callout.toTextStyle(),
                color = colors.onyx,
            )
        }
        Spacer(Modifier.height(RdSpacing.xs))
        LinearProgressIndicator(
            progress = { progress.titleProgress.toFloat() },
            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)),
            color = colors.onyx,
            trackColor = colors.fog,
        )
        progress.nextTitle?.let { next ->
            Text(
                "Sıradaki: ${next.label} (${progress.nextTitleRemaining} MDP kaldı)",
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                modifier = Modifier.padding(top = RdSpacing.xxs),
            )
        }
        progress.weeklySummary?.let { weekly ->
            Text(
                weekly.messageTitle
                    ?: "Bu hafta: ${weekly.analysesCount} analiz, ${weekly.reportsCount} rapor",
                style = RdFontStyle.Footnote.toTextStyle(),
                color = colors.greenDark,
                modifier = Modifier.padding(top = RdSpacing.xs),
            )
        }
    }
}

/** Port of the titles-ladder catalog sheet `ProfessionalProgressHomeCard.swift`'s `onTap` opens —
 * simple checkmark/lock list rather than iOS's richer per-title illustration, same simplification
 * policy as the rest of this feature slice (accent colors/icons not ported, see
 * [ProfessionalProgressTitle]'s doc comment). */
@Composable
fun ProfessionalTitlesSheet(progress: ProfessionalProgressSummary) {
    val colors = RdTheme.colors
    Column(modifier = Modifier.padding(RdSpacing.lg)) {
        Text("Uzmanlık Seviyeleri", style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
        Text(
            "${progress.profile.totalMdp} MDP",
            style = RdFontStyle.Footnote.toTextStyle(),
            color = colors.slate,
            modifier = Modifier.padding(bottom = RdSpacing.md),
        )
        ProfessionalProgressTitle.entries.forEach { title ->
            val unlocked = progress.profile.totalMdp >= title.threshold
            val isCurrent = title == progress.currentTitle
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = RdSpacing.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (unlocked) Icons.Filled.EmojiEvents else Icons.Filled.Lock,
                    contentDescription = null,
                    tint = if (unlocked) colors.onyx else colors.slate,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(RdSpacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        title.label,
                        style = RdFontStyle.Callout.toTextStyle(),
                        color = if (unlocked) colors.onyx else colors.slate,
                    )
                    Text("${title.threshold} MDP", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
                if (isCurrent) {
                    Text("Şu an", style = RdFontStyle.Caption.toTextStyle(), color = colors.greenDark)
                }
            }
        }
    }
}
