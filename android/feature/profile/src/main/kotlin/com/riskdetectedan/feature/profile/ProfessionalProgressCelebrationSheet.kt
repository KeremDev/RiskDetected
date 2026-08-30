package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.progress.ProfessionalProgressBadge
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdConfettiView
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import kotlinx.coroutines.delay

/**
 * Real port of `ProfessionalProgressCelebrationSheet.swift` — auto-shown whenever
 * `summary.pendingCelebration` (first unseen real badge row) is non-null, matches `onClose`'s
 * `markBadgeSeen` + refresh pair exactly (see [ProfileScreen]'s wiring). Confetti burst is a real
 * (not decorative-only) Compose animation, [RdConfettiView] (`core:designsystem`, extracted
 * 2026-08-09 so `OBPlanSummaryScreen`'s own reveal moment could reuse the same real burst instead
 * of rebuilding it) — 8 pieces, per-piece delay/color/rotation lifted straight from the Swift
 * `ConfettiPiece` literals, rather than the SwiftUI-specific `.spring().delay()` modifier chain
 * it can't share verbatim.
 */
@Composable
fun ProfessionalProgressCelebrationSheet(badge: ProfessionalProgressBadge, onClose: () -> Unit) {
    val colors = RdTheme.colors
    var animate by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(100)
        animate = true
    }
    val iconScale by animateFloatAsState(
        targetValue = if (animate) 1f else 0.94f,
        animationSpec = spring(dampingRatio = 0.72f, stiffness = 180f),
        label = "badgeIconScale",
    )

    Box(modifier = Modifier.fillMaxWidth().background(colors.paper)) {
        RdConfettiView(
            isActive = animate,
            modifier = Modifier.fillMaxWidth().height(168.dp).padding(horizontal = RdSpacing.lg, vertical = RdSpacing.sm),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = RdSpacing.xl)
                .padding(top = 72.dp, bottom = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .graphicsLayer { scaleX = iconScale; scaleY = iconScale }
                    .clip(RoundedCornerShape(RdRadius.xl))
                    .background(colors.greenSoft),
                contentAlignment = Alignment.Center,
            ) {
                Icon(sfIconToImageVector(badge.iconName), contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(34.dp))
            }
            Spacer(Modifier.height(RdSpacing.lg))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(colors.greenSoft)
                    .padding(horizontal = 14.dp, vertical = 7.dp),
            ) {
                Text(stringResource(RdR.string.rd_tebrikler), style = RdFontStyle.Footnote.toTextStyle(), color = colors.greenDark)
            }
            Spacer(Modifier.height(9.dp))
            Text(badge.localizedTitle, style = RdFontStyle.Title2.toTextStyle(), color = colors.black, textAlign = TextAlign.Center)
            Spacer(Modifier.height(9.dp))
            Text(badge.localizedSubtitle, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
            Spacer(Modifier.height(RdSpacing.sm))
            RdPrimaryButton(text = stringResource(RdR.string.rd_tamam), onClick = onClose, style = RdButtonStyle.Green, showArrow = false)
        }

        IconButton(
            onClick = onClose,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = RdSpacing.lg, end = RdSpacing.xl)
                .size(38.dp)
                .clip(CircleShape)
                .background(colors.white)
                .border(1.dp, colors.line, CircleShape),
        ) {
            Icon(Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), tint = colors.black, modifier = Modifier.size(14.dp))
        }
    }
}
