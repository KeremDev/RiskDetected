package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.core.designsystem.rdAnalysisCanvasTitle

/**
 * Port of App/Views/Home/CanvasSheet.swift (Faz N of the core-flow-full-parity roadmap) — the
 * "Odaklı Analiz" canvas picker: 2-row horizontal scroll rail, 16 real canvases
 * ([AnalysisCanvas.all]), tier-gated lock badges. Selection rule mirrors `CanvasSheet.select(_:)`
 * exactly: free tier is single-select (picking a new canvas replaces the set), paid tiers are
 * multi-select with a "can't drop below 1 selected" guard; tapping a locked (tier-gated) canvas
 * calls [onUpgradeRequested] instead of selecting it.
 */
@Composable
fun CanvasSheet(
    selected: Set<AnalysisCanvas>,
    onSelectedChange: (Set<AnalysisCanvas>) -> Unit,
    userTier: SubscriptionTier,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    onUpgradeRequested: () -> Unit,
) {
    val colors = RdTheme.colors

    fun select(canvas: AnalysisCanvas) {
        if (canvas.isPaid && !userTier.includes(canvas.minTier)) {
            onUpgradeRequested()
            return
        }
        onSelectedChange(nextCanvasSelection(selected, canvas, userTier.isPaid))
    }

    Column(modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg).padding(bottom = RdSpacing.md),
            verticalAlignment = Alignment.Top,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(stringResource(RdR.string.rd_odakli_analiz), style = RdFontStyle.Title2.toTextStyle(), color = colors.black)
                Spacer(Modifier.height(4.dp))
                Text(
                    stringResource(
                        if (userTier.isPaid) RdR.string.rd_coklu_odak_sec else RdR.string.rd_tek_odak_sec,
                    ),
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.slate,
                )
            }
            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(colors.white)
                    .border(1.dp, colors.line, CircleShape),
            ) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), tint = colors.black, modifier = Modifier.size(14.dp))
            }
        }

        LazyHorizontalGrid(
            rows = GridCells.Fixed(2),
            modifier = Modifier.fillMaxWidth().height(172.dp).padding(horizontal = RdSpacing.md),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(AnalysisCanvas.all, key = { it.id }) { canvas ->
                CanvasCard(
                    canvas = canvas,
                    isActive = selected.contains(canvas),
                    isLocked = canvas.isPaid && !userTier.includes(canvas.minTier),
                    onClick = { select(canvas) },
                )
            }
        }

        Spacer(Modifier.height(RdSpacing.sm))
        RdPrimaryButton(
            text = stringResource(RdR.string.rd_onayla_devam_et),
            onClick = onConfirm,
            style = RdButtonStyle.Onyx,
            modifier = Modifier.padding(horizontal = RdSpacing.lg),
        )
        Spacer(Modifier.height(RdSpacing.md))
    }
}

/**
 * "Genel" is the absence of a narrower focus, so combining it with a specific canvas makes the
 * legacy primary `canvas` field misleading (for example `[general, sector]` used to be stored as
 * `general` after sorting). Keep paid multi-selection for specific canvases, but make General
 * mutually exclusive so the focus shown in history/report always reflects the user's choice.
 */
internal fun nextCanvasSelection(
    selected: Set<AnalysisCanvas>,
    tapped: AnalysisCanvas,
    isPaidTier: Boolean,
): Set<AnalysisCanvas> {
    if (!isPaidTier || tapped == AnalysisCanvas.general) return setOf(tapped)

    val specificSelection = selected - AnalysisCanvas.general
    return if (tapped in specificSelection) {
        if (specificSelection.size > 1) specificSelection - tapped else specificSelection
    } else {
        specificSelection + tapped
    }
}

@Composable
private fun CanvasCard(canvas: AnalysisCanvas, isActive: Boolean, isLocked: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val accent = if (canvas.minTier == SubscriptionTier.Pro) colors.green else colors.planPlus
    val accentDark = if (canvas.minTier == SubscriptionTier.Pro) colors.greenDark else colors.planPlusDark
    val accentSoft = if (canvas.minTier == SubscriptionTier.Pro) colors.greenSoft else colors.planPlusSoft
    val background = if (isActive) colors.selected else colors.white
    val textColor = if (isActive) Color.White else colors.black
    val borderColor = if (isActive) colors.selected else if (canvas.isPaid) accent.copy(alpha = 0.55f) else colors.line
    val iconBg = if (isActive) colors.green else if (canvas.isPaid) accentSoft else colors.fog
    val iconTint = if (isActive) Color.White else if (canvas.isPaid) accentDark else colors.black

    Box(
        modifier = Modifier
            .width(106.dp)
            .height(82.dp)
            .shadow(
                elevation = if (canvas.isPaid && !isActive) 4.dp else 0.dp,
                shape = RoundedCornerShape(14.dp),
                ambientColor = accent.copy(alpha = 0.14f),
                spotColor = accent.copy(alpha = 0.14f),
            )
            .clip(RoundedCornerShape(14.dp))
            .background(background)
            .border(if (canvas.isPaid && !isActive) 1.5.dp else 1.dp, borderColor, RoundedCornerShape(14.dp))
            .alpha(if (isLocked) 0.86f else 1f)
            .clickable(onClick = onClick),
    ) {
        Column(modifier = Modifier.padding(9.dp)) {
            Box(
                modifier = Modifier.size(28.dp).clip(RoundedCornerShape(8.dp)).background(iconBg),
                contentAlignment = Alignment.Center,
            ) {
                Icon(canvasIcon(canvas.icon), contentDescription = null, tint = iconTint, modifier = Modifier.size(14.dp))
            }
            Spacer(Modifier.height(7.dp))
            Text(rdAnalysisCanvasTitle(canvas.id, canvas.title), style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 11.sp), color = textColor, maxLines = 2)
        }

        if (canvas.isPaid) {
            Column(modifier = Modifier.align(Alignment.TopEnd).padding(top = 6.dp, end = 6.dp), horizontalAlignment = Alignment.End) {
                TierBadge(tier = canvas.minTier)
                if (isLocked) {
                    Spacer(Modifier.height(4.dp))
                    LockedBadge()
                }
            }
        }
    }
}

@Composable
private fun TierBadge(tier: SubscriptionTier) {
    val colors = RdTheme.colors
    val isPro = tier == SubscriptionTier.Pro
    val accent = if (isPro) colors.green else colors.planPlus
    // Material Icons has no licensed/system crown counterpart in this Compose set. The premium
    // medal is the closest optically safe Android equivalent to iOS `crown.fill`; Pro keeps the
    // distinct `star.fill` identity from the iOS tier contract.
    val badgeIcon = if (isPro) Icons.Filled.Star else Icons.Filled.WorkspacePremium
    val badgeLabel = stringResource(if (isPro) RdR.string.rd_pro else RdR.string.rd_plus).uppercase()
    Row(
        modifier = Modifier
            .height(16.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(accent)
            .padding(horizontal = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(badgeIcon, contentDescription = null, tint = Color.White, modifier = Modifier.size(8.dp))
        Spacer(Modifier.width(2.dp))
        Text(
            badgeLabel,
            style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 8.sp),
            color = Color.White,
        )
    }
}

@Composable
private fun LockedBadge() {
    Row(
        modifier = Modifier
            .height(15.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(Color(0xFFFFF1B8))
            .padding(horizontal = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Lock, contentDescription = null, tint = Color(0xFF8A6500), modifier = Modifier.size(7.dp))
        Spacer(Modifier.width(2.dp))
        Text(stringResource(RdR.string.rd_ki_li_tli), style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 7.sp), color = Color(0xFF8A6500))
    }
}

private fun canvasIcon(key: String): ImageVector = when (key) {
    "sparkles" -> Icons.Filled.AutoAwesome
    "shield.lefthalf.filled" -> Icons.Filled.Shield
    "gearshape.2.fill" -> Icons.Filled.Settings
    "exclamationmark.triangle.fill" -> Icons.Filled.Warning
    "bolt.fill" -> Icons.Filled.Bolt
    "building.2.fill" -> Icons.Filled.Business
    "flame.fill" -> Icons.Filled.LocalFireDepartment
    "wrench.and.screwdriver.fill" -> Icons.Filled.Build
    "gauge.with.dots.needle.67percent" -> Icons.Filled.Speed
    "burst.fill" -> Icons.Filled.Whatshot
    "leaf.fill" -> Icons.Filled.Eco
    "scroll.fill" -> Icons.Filled.Description
    "figure.climbing" -> Icons.Filled.Terrain
    "truck.box.fill" -> Icons.Filled.LocalShipping
    "star.square.fill" -> Icons.Filled.Star
    else -> Icons.Filled.AutoAwesome
}
