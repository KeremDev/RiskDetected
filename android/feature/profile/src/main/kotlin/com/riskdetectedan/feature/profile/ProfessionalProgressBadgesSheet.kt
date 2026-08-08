package com.riskdetectedan.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Real port of `ProfessionalProgressBadgesView.swift`'s curated 6-badge catalog grid ("Başarılarım",
 * opened from [ProfileHero]'s rosette button — matches iOS's `showProfileBadges` trigger under the
 * display name). Earned state is computed the same way as the Swift `isEarned`: earned if the
 * real `professional_progress_badges` row exists for that key (server already unlocked it) OR — for
 * a badge this specific catalog subset also knows the client-side threshold for — the live summary
 * numbers already clear it (covers the gap between "badge exists on server" and "unlock RPC hasn't
 * run yet this session").
 */
@Composable
fun ProfessionalProgressBadgesSheet(summary: ProfessionalProgressSummary, onDismiss: () -> Unit) {
    val colors = RdTheme.colors
    val earnedKeys = remember(summary) { summary.badges.map { it.badgeKey }.toSet() }
    val items = BadgeCatalog.defaults.map { item -> item to item.isEarned(summary, earnedKeys) }

    Column(modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg).padding(bottom = RdSpacing.md),
            verticalAlignment = Alignment.Top,
        ) {
            Text(
                "Başarılarım",
                style = RdFontStyle.Title2.toTextStyle(),
                color = colors.black,
                modifier = Modifier.weight(1f),
            )
            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(colors.white)
                    .border(1.dp, colors.line, CircleShape),
            ) {
                Icon(Icons.Filled.Close, contentDescription = "Kapat", tint = colors.black, modifier = Modifier.size(14.dp))
            }
        }

        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier.fillMaxWidth().heightIn(max = 320.dp).padding(horizontal = RdSpacing.lg),
            horizontalArrangement = Arrangement.spacedBy(RdSpacing.sm),
            verticalArrangement = Arrangement.spacedBy(RdSpacing.sm),
        ) {
            items(items, key = { it.first.key }) { (item, earned) -> BadgeTile(item, earned) }
        }
        Spacer(Modifier.height(RdSpacing.lg))
    }
}

@Composable
private fun BadgeTile(item: BadgeCatalog, earned: Boolean) {
    val colors = RdTheme.colors
    val iconBackground = if (earned) item.accent.copy(alpha = 0.20f) else colors.fog
    val iconForeground = if (earned) item.accent else colors.slate.copy(alpha = 0.78f)
    val cardBackground = if (earned) colors.white else colors.white.copy(alpha = 0.72f)
    val borderColor = if (earned) item.accent.copy(alpha = 0.25f) else colors.line.copy(alpha = 0.65f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(108.dp)
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(cardBackground)
            .border(if (earned) 1.2.dp else 1.dp, borderColor, RoundedCornerShape(RdRadius.lg))
            .padding(horizontal = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(contentAlignment = Alignment.TopEnd) {
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .background(iconBackground)
                    .border(3.dp, colors.white, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(item.icon, contentDescription = null, tint = iconForeground, modifier = Modifier.size(23.dp))
            }
            Box(
                modifier = Modifier
                    .size(20.dp)
                    .clip(CircleShape)
                    .background(colors.white),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (earned) Icons.Filled.EmojiEvents else Icons.Filled.Lock,
                    contentDescription = null,
                    tint = if (earned) item.accent else colors.slate,
                    modifier = Modifier.size(12.dp),
                )
            }
        }
        Spacer(Modifier.height(9.dp))
        Text(
            item.title,
            style = RdFontStyle.Caption.toTextStyle(),
            color = if (earned) colors.black else colors.slate,
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

private enum class BadgeRequirement { ReportCount, CompetencyCount, HighRisk, ActiveDays }

private data class BadgeCatalog(
    val key: String,
    val title: String,
    val icon: ImageVector,
    val accent: Color,
    val requirement: BadgeRequirement,
    val threshold: Int = 0,
) {
    fun isEarned(summary: ProfessionalProgressSummary, earnedKeys: Set<String>): Boolean {
        if (earnedKeys.contains(key)) return true
        return when (requirement) {
            BadgeRequirement.ReportCount -> summary.profile.totalReports >= threshold
            BadgeRequirement.CompetencyCount ->
                summary.competencies.count { it.findingCount > 0 || it.reportCount > 0 } >= threshold
            BadgeRequirement.HighRisk -> summary.profile.highFindings + summary.profile.criticalFindings > 0
            BadgeRequirement.ActiveDays -> summary.profile.activeDays >= threshold
        }
    }

    companion object {
        val defaults = listOf(
            BadgeCatalog("reports:10", "10 Rapor", sfIconToImageVector("medal.fill"), Color(0xFF0E9F6E), BadgeRequirement.ReportCount, 10),
            BadgeCatalog("reports:50", "50 Rapor", sfIconToImageVector("trophy.fill"), Color(0xFFD97706), BadgeRequirement.ReportCount, 50),
            BadgeCatalog("reports:100", "Yüz Rapor", sfIconToImageVector("trophy.fill"), Color(0xFFB45309), BadgeRequirement.ReportCount, 100),
            BadgeCatalog("competency:5", "5 Alan", sfIconToImageVector("square.grid.3x2.fill"), Color(0xFF2563EB), BadgeRequirement.CompetencyCount, 5),
            BadgeCatalog("risk:first_high", "Yüksek Risk", sfIconToImageVector("exclamationmark.triangle.fill"), Color(0xFFB42318), BadgeRequirement.HighRisk),
            BadgeCatalog("active_days:30", "30 Aktif Gün", sfIconToImageVector("calendar.badge.checkmark"), Color(0xFF7C3AED), BadgeRequirement.ActiveDays, 30),
        )
    }
}
