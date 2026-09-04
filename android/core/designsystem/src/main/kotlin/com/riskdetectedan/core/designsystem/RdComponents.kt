package com.riskdetectedan.core.designsystem

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * Android port of the core-value-flow (post-onboarding) shared component set — the counterpart to
 * [RdOnboardingComponents] for Capture/Analysis/Reports/Profile/Paywall (Faz F of the core-flow
 * visual pass). iOS has no equivalent single shared file for these screens either (each View
 * builds its own row/card/chip inline, same as onboarding was before `OBComponents.swift`) — these
 * are a genuine Android-side consolidation, not a literal file-for-file port. Colors/spacing come
 * from the same [RdTheme]/[RdSpacing]/[RdRadius] tokens as everywhere else.
 */

/** Simple title(+back) header for non-onboarding screens — no progress bar, unlike
 * [RdTopBar] which is onboarding-specific. */
@Composable
fun RdScreenHeader(title: String, onBack: (() -> Unit)? = null, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = RdSpacing.md, vertical = RdSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack, modifier = Modifier.size(40.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.rd_geri), tint = RdTheme.colors.black)
            }
            Spacer(Modifier.width(RdSpacing.xs))
        }
        Text(title, style = RdFontStyle.Title2.toTextStyle(), color = RdTheme.colors.black)
    }
}

/** Generic selectable/tappable list row — History/Reports/Company's shared shape. Unlike
 * onboarding's [RdCard] (which always shows a selection indicator), this has a free-form
 * [trailing] slot (risk chip, chevron, plain text, or nothing) since these screens aren't
 * pickers. */
@Composable
fun RdListRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    iconTint: Color? = null,
    iconBackground: Color? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val colors = RdTheme.colors
    Pressable(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.black.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg)),
        onClick = onClick ?: {},
    ) {
        Row(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxWidth()
                .padding(horizontal = RdSpacing.md, vertical = RdSpacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(RdRadius.sm))
                        .background(iconBackground ?: colors.fog),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, contentDescription = null, tint = iconTint ?: colors.graphite, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(RdSpacing.sm))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
                if (subtitle != null) {
                    Text(subtitle, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
                }
            }
            if (trailing != null) {
                Spacer(Modifier.width(RdSpacing.sm))
                trailing()
            } else if (onClick != null) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = colors.slate,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

@Composable
private fun RiskLevel.turkishLabel(): String = stringResource(
    when (this) {
        RiskLevel.Critical -> R.string.rd_risk_kritik
        RiskLevel.High -> R.string.rd_risk_yuksek
        RiskLevel.Medium -> R.string.rd_risk_orta
        RiskLevel.Low -> R.string.rd_risk_dusuk
        RiskLevel.Unknown -> R.string.rd_risk_bilinmiyor
    },
)

@Composable
private fun RiskLevel.textColor(): Color = when (this) {
    RiskLevel.Critical -> RdTheme.colors.criticalText
    RiskLevel.High -> RdTheme.colors.highText
    RiskLevel.Medium -> RdTheme.colors.mediumText
    RiskLevel.Low -> RdTheme.colors.lowText
    RiskLevel.Unknown -> RdTheme.colors.slate
}

/** Small risk-level pill — reuses [RiskLevel.color]/[RiskLevel.backgroundColor] (already used for
 * plain text-color mapping in the pre-visual-pass screens), adds a real chip shape + a dedicated
 * text-color variant (darker than the raw accent, for AA contrast on the tinted background). */
@Composable
fun RdRiskChip(level: RiskLevel, label: String? = null, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(level.backgroundColor())
            .padding(horizontal = RdSpacing.sm, vertical = 4.dp),
    ) {
        Text(
            label ?: level.turkishLabel(),
            style = RdFontStyle.Caption.toTextStyle(),
            color = level.textColor(),
        )
    }
}

/** White rounded card with an optional small uppercase section label above it — Profile's
 * grouping shape. */
@Composable
fun RdSectionCard(
    modifier: Modifier = Modifier,
    title: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = RdTheme.colors
    Column(modifier = modifier) {
        if (title != null) {
            Text(
                title.uppercase(),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                modifier = Modifier.padding(start = RdSpacing.xxs, bottom = RdSpacing.xxs),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(RdRadius.lg))
                .background(colors.white)
                .border(1.dp, colors.black.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg))
                .padding(RdSpacing.md),
            content = content,
        )
    }
}

/** Centered icon+title+subtitle for empty lists (no History/Company/Reports screen has one yet —
 * every list either has data or shows nothing). */
@Composable
fun RdEmptyState(icon: ImageVector, title: String, modifier: Modifier = Modifier, subtitle: String? = null) {
    val colors = RdTheme.colors
    Column(
        modifier = modifier.fillMaxWidth().padding(RdSpacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(RoundedCornerShape(RdRadius.xl))
                .background(colors.fog),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = colors.slate, modifier = Modifier.size(28.dp))
        }
        Spacer(Modifier.height(RdSpacing.sm))
        // `onyx` is intentionally fixed black for inverse surfaces. Empty states sit directly
        // on the dynamic paper background, so their title must use the dynamic foreground token.
        Text(title, style = RdFontStyle.Callout.toTextStyle(), color = colors.black, textAlign = TextAlign.Center)
        if (subtitle != null) {
            Spacer(Modifier.height(RdSpacing.xxs))
            Text(subtitle, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
        }
    }
}
