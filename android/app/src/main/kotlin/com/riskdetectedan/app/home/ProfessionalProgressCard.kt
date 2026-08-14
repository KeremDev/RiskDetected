package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowOutward
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.data.progress.ProfessionalProgressTitle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.core.designsystem.professionalProgressTitleLabel
import java.text.NumberFormat
import java.util.Locale

/**
 * Real port of `ProfessionalProgressHomeCard.swift`'s `.compactStrip` style (the amber MDP card
 * below "Taramayı Başlat" on the real Home screenshot) — flame icon, "used / nextThreshold MDP"
 * + "%NN" line, progress capsule, "Kıdemini yükselt · <nextTitle>" CTA line, tap opens
 * [ProfessionalTitlesSheet]. `.showcase` style (Profile's richer title-ladder card) not ported —
 * ProfileScreen keeps its own simpler `ProfessionalProgressSection` text summary, unchanged.
 */
@Composable
fun ProfessionalProgressCard(progress: ProfessionalProgressSummary, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val accent = colors.planPlus
    val percent = (progress.titleProgress * 100).toInt()
    val nextThreshold = progress.nextTitle?.threshold ?: progress.currentTitle.threshold
    val formatter = remember { NumberFormat.getIntegerInstance(Locale("tr")) }

    val shape = RoundedCornerShape(RdRadius.lg)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(elevation = 10.dp, shape = shape, ambientColor = accent.copy(alpha = 0.20f), spotColor = accent.copy(alpha = 0.20f))
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(colors.planPlusSoft.copy(alpha = 0.86f), colors.paper, colors.greenSoft.copy(alpha = 0.32f)),
                ),
            )
            .border(1.dp, accent.copy(alpha = 0.24f), shape)
            .clickable(onClick = onClick)
            .padding(horizontal = RdSpacing.md, vertical = RdSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(38.dp).clip(CircleShape).background(accent.copy(alpha = 0.20f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.LocalFireDepartment, contentDescription = null, tint = accent, modifier = Modifier.size(21.dp))
        }
        Spacer(Modifier.width(RdSpacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(formatter.format(progress.profile.totalMdp), style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
                Text(
                    stringResource(RdR.string.rd_mdp_progress_format, formatter.format(nextThreshold)),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                )
                Spacer(Modifier.weight(1f))
                Text(stringResource(RdR.string.rd_yuzde_deger_format, percent), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
            Spacer(Modifier.height(RdSpacing.xxs))
            LinearProgressIndicator(
                progress = { progress.titleProgress.toFloat() },
                modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)),
                color = accent,
                trackColor = accent.copy(alpha = 0.16f),
            )
            Spacer(Modifier.height(RdSpacing.xxs))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.ArrowOutward, contentDescription = null, tint = accent, modifier = Modifier.size(12.dp))
                Spacer(Modifier.width(2.dp))
                Text(stringResource(RdR.string.rd_kidemini_yukselt), style = RdFontStyle.Caption.toTextStyle(), color = accent)
                progress.nextTitle?.let { next ->
                    Text(
                        stringResource(
                            RdR.string.rd_ayrac_etiket_format,
                            professionalProgressTitleLabel(next.key),
                        ),
                        style = RdFontStyle.Caption.toTextStyle(),
                        color = colors.slate,
                    )
                }
            }
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
        Text(stringResource(RdR.string.rd_uzmanlik_seviyeleri), style = RdFontStyle.Title3.toTextStyle(), color = colors.black)
        Text(
            stringResource(RdR.string.rd_mdp_total_format, progress.profile.totalMdp),
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
                    tint = if (unlocked) colors.black else colors.slate,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(RdSpacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        professionalProgressTitleLabel(title.key),
                        style = RdFontStyle.Callout.toTextStyle(),
                        color = if (unlocked) colors.black else colors.slate,
                    )
                    Text(stringResource(RdR.string.rd_mdp_esigi_format, title.threshold), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
                if (isCurrent) {
                    Text(stringResource(RdR.string.rd_su_an), style = RdFontStyle.Caption.toTextStyle(), color = colors.greenDark)
                }
            }
        }
    }
}
