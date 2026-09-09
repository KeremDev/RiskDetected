package com.riskdetectedan.core.designsystem

import androidx.compose.ui.res.stringResource

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Android port of App/Views/Onboarding/V2/Components/OBComponents.swift — the shared component
 * library iOS's onboarding+auth screens build on (2026-08-08 visual-design pass). Colors/spacing
 * match `RdColor`/`RdSpacing` exactly (already 1:1 with `RDColor.swift`/`RDSpacing.swift`, no new
 * tokens needed). Deliberately simplified vs. the Swift originals, documented per component, not
 * silently dropped:
 * - No custom Canvas-drawn illustrations (hard hat badge, city skyline, calendar) — this file
 *   only provides the illustration *container* ([RdHeroTile]); each screen supplies a Material
 *   icon instead of a bespoke vector drawing.
 * - [Pressable]'s 0.97 scale-on-press is ported; [RdPrimaryButton]'s infinite arrow-nudge loop
 *   is ported (cheap via `rememberInfiniteTransition`). [RdSelectionCounter]'s pulse-on-change,
 *   OTP-box blinking-caret, and the auth hero's spinning-arc icon are NOT ported in this pass —
 *   more involved, lower value, deferred to Faz D.
 */

// ---- Press feedback (OBPressStyle) --------------------------------------------------------

/** Scales to 0.97 on press — matches OBPressStyle's `obSnap` (0.1s) closely enough with
 * Compose's default float animation; the exact cubic-bezier curve isn't reproduced, same
 * "good enough" bar as everything else in this pass. Every selectable component below is built
 * on this instead of a bare `clickable` modifier. */
@Composable
fun Pressable(
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    content: @Composable BoxScope.() -> Unit,
) {
    var pressed by remember { mutableStateOf(false) }
    // pointerInput(Unit) survives recompositions. Without rememberUpdatedState it keeps the
    // first onClick lambda forever, so buttons that become enabled after a selection still run
    // their initial disabled/no-op callback (sector picker and paywall CTAs are concrete cases).
    val currentOnClick by rememberUpdatedState(onClick)
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, label = "scaleOnPress")
    Box(
        modifier = modifier
            .scale(scale)
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = {
                        pressed = true
                        tryAwaitRelease()
                        pressed = false
                    },
                    onTap = { currentOnClick() },
                )
            },
        content = content,
    )
}

// ---- RdPrimaryButton (OBPrimaryButton) ----------------------------------------------------

enum class RdButtonStyle { Onyx, Green, Gold }

/** Mirrors OBPrimaryButton: 56dp height, 14dp corner, trailing arrow with an infinite nudge
 * loop, disabled/loading states. [loadingLabel] swaps in while [loading] is true, matching the
 * Swift version's `loadingTitle` override. */
@Composable
fun RdPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    style: RdButtonStyle = RdButtonStyle.Onyx,
    enabled: Boolean = true,
    loading: Boolean = false,
    loadingLabel: String? = null,
    showArrow: Boolean = true,
) {
    val colors = RdTheme.colors
    val bg = when {
        !enabled -> colors.black.copy(alpha = 0.08f)
        style == RdButtonStyle.Green -> colors.green
        style == RdButtonStyle.Gold -> Color(0xFFD4A106)
        else -> colors.cta
    }
    val contentColor = if (!enabled) colors.black.copy(alpha = 0.35f) else Color.White

    Pressable(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(bg),
        onClick = { if (enabled && !loading) onClick() },
    ) {
        Row(
            modifier = Modifier.align(Alignment.Center),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = contentColor,
                    strokeWidth = 2.dp,
                )
                Spacer(Modifier.width(RdSpacing.xs))
            }
            Text(
                text = if (loading && loadingLabel != null) loadingLabel else text,
                color = contentColor,
                style = RdFontStyle.Callout.toTextStyle(),
            )
            if (showArrow && !loading) {
                Spacer(Modifier.width(RdSpacing.xs))
                NudgingArrow(tint = contentColor)
            }
        }
    }
}

/** OBPrimaryButton's infinite "nudge" hint: the arrow drifts right then resets, ~0.7s loop. */
@Composable
private fun NudgingArrow(tint: Color) {
    val transition = rememberInfiniteTransition(label = "nudge")
    val offsetX by transition.animateFloat(
        initialValue = 0f,
        targetValue = 4f,
        animationSpec = infiniteRepeatable(animation = tween(700, easing = LinearEasing)),
        label = "nudge-offset",
    )
    Icon(
        imageVector = Icons.AutoMirrored.Filled.ArrowForward,
        contentDescription = null,
        tint = tint,
        modifier = Modifier.size(18.dp).offset(x = offsetX.dp),
    )
}

// ---- RdHeroTile (OBHeroTile / OBHeroTint) --------------------------------------------------

enum class RdHeroTint { Neutral, Green, Warm, Cool, Dusk }

/** Mirrors OBHeroTile: 108×80dp rounded(20dp) illustration container with a diagonal gradient
 * background per [tint] and a 1dp border. [content] is the icon/illustration slot (a Material
 * `Icon` in this pass, not a custom Canvas drawing — see file doc comment). */
@Composable
fun RdHeroTile(tint: RdHeroTint, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val (gradientColors, borderColor) = heroTintColors(tint)
    Box(
        modifier = modifier
            .size(width = 108.dp, height = 80.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.linearGradient(gradientColors, start = Offset(0f, 0f)))
            .border(1.dp, borderColor, RoundedCornerShape(20.dp))
            .padding(10.dp),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

@Composable
private fun heroTintColors(tint: RdHeroTint): Pair<List<Color>, Color> {
    val colors = RdTheme.colors
    return when (tint) {
        RdHeroTint.Neutral -> listOf(colors.white, colors.cloud, colors.fog) to colors.black.copy(alpha = 0.05f)
        RdHeroTint.Green -> listOf(colors.white, Color(0xFFF0FAF3), Color(0xFFE1F4E8)) to colors.green.copy(alpha = 0.14f)
        RdHeroTint.Warm -> listOf(colors.white, Color(0xFFFCF6EE), Color(0xFFF7EDDA)) to colors.high.copy(alpha = 0.14f)
        RdHeroTint.Cool -> listOf(colors.white, Color(0xFFF1F4F9), Color(0xFFE6ECF4)) to colors.info.copy(alpha = 0.14f)
        RdHeroTint.Dusk -> listOf(Color(0xFF1B1E20), Color(0xFF131516), Color(0xFF0B0D0E)) to colors.white.copy(alpha = 0.08f)
    }
}

// ---- RdTopBar + RdProgress (OBTopBar / OBProgress) -----------------------------------------

/** Mirrors OBTopBar: back chevron (40dp tap target) + segmented progress bar + "NN / total"
 * trailing label. [onBack] null hides the back button (matches `showBack` on the Swift side). */
@Composable
fun RdTopBar(step: Int, total: Int, onBack: (() -> Unit)? = null, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = RdSpacing.lg, vertical = RdSpacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack, modifier = Modifier.size(40.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.rd_geri), tint = RdTheme.colors.onyx)
            }
        } else {
            Spacer(Modifier.size(40.dp))
        }
        Spacer(Modifier.width(RdSpacing.sm))
        RdProgress(step = step, total = total, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(RdSpacing.sm))
        Text(
            text = "%02d / %02d".format(step, total),
            style = RdFontStyle.Data.toTextStyle(),
            color = RdTheme.colors.slate,
        )
    }
}

/** Mirrors OBProgress: N capsule segments, 6dp gaps, 5dp tall — done segments filled green,
 * current filled onyx, upcoming = track color. The Swift version's per-segment fill-width
 * animation + checkmark-circle overlay on done segments isn't ported — a static fill state per
 * segment reads clearly enough without it for this pass. */
@Composable
fun RdProgress(step: Int, total: Int, modifier: Modifier = Modifier) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(total) { index ->
            val segmentNumber = index + 1
            val fillColor = when {
                segmentNumber < step -> RdTheme.colors.green
                segmentNumber == step -> RdTheme.colors.onyx
                else -> RdTheme.colors.onyx.copy(alpha = 0.08f)
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(5.dp)
                    .clip(RoundedCornerShape(50))
                    .background(fillColor),
            )
        }
    }
}

// ---- RdCard (OBCard) — vertical list picker row --------------------------------------------

/** Mirrors OBCard: full-width selectable row, leading icon + title/subtitle + a
 * circle-or-rounded-square selection indicator ([multi] picks the shape, matching the Swift
 * single-vs-multi-select visual distinction). [iconTint]/[iconBackground] override the default
 * selection-dependent (fog/onyx, graphite/white) icon coloring — mirrors OBHazardClassView's
 * `hazardIcon` helper, which bypasses OBCard's own icon slot to keep the icon permanently
 * severity-tinted (rdCritical/rdHigh/rdLow + their Bg variants) regardless of selection state;
 * pass both to get that exact behavior, leave both null for the default onyx/fog look. */
@Composable
fun RdCard(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    iconTint: Color? = null,
    iconBackground: Color? = null,
    selected: Boolean = false,
    multi: Boolean = false,
    titleStyle: RdFontStyle = RdFontStyle.Callout,
) {
    val colors = RdTheme.colors
    val borderWidth = if (selected) 2.dp else 1.dp
    val borderColor = if (selected) colors.onyx else colors.onyx.copy(alpha = 0.06f)

    Pressable(
        modifier = modifier
            .fillMaxWidth()
            .height(if (icon != null || subtitle != null) 72.dp else 64.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(colors.white)
            .border(BorderStroke(borderWidth, borderColor), RoundedCornerShape(16.dp)),
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(iconBackground ?: if (selected) colors.onyx else colors.fog),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        icon,
                        contentDescription = null,
                        tint = iconTint ?: if (selected) colors.white else colors.graphite,
                        modifier = Modifier.size(18.dp),
                    )
                }
                Spacer(Modifier.width(RdSpacing.sm))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = titleStyle.toTextStyle(), color = colors.onyx)
                if (subtitle != null) {
                    Text(subtitle, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
                }
            }
            Spacer(Modifier.width(RdSpacing.sm))
            SelectionIndicator(selected = selected, multi = multi)
        }
    }
}

@Composable
private fun SelectionIndicator(selected: Boolean, multi: Boolean) {
    val colors = RdTheme.colors
    val shape = if (multi) RoundedCornerShape(7.dp) else CircleShape
    Box(
        modifier = Modifier
            .size(24.dp)
            .clip(shape)
            .background(if (selected) colors.onyx else Color.Transparent)
            .border(1.5.dp, if (selected) Color.Transparent else colors.onyx.copy(alpha = 0.18f), shape),
        contentAlignment = Alignment.Center,
    ) {
        if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = colors.white, modifier = Modifier.size(12.dp))
        }
    }
}

// ---- RdChipTile (Sector's bespoke grid tile) ------------------------------------------------

/** Mirrors OBSectorView's `sectorCard` — its 78pt content frame plus 9pt outer padding on each
 * edge produces a 96pt card. The old Android port treated 78dp as the *entire* tile, so subtitle
 * baselines were clipped on real devices (and especially with larger font scale). `heightIn`
 * keeps the iOS normal-state height while still allowing accessibility text to grow. */
@Composable
fun RdChipTile(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    selected: Boolean = false,
) {
    val colors = RdTheme.colors
    val borderWidth = if (selected) 2.dp else 1.dp
    val borderColor = if (selected) colors.onyx else colors.onyx.copy(alpha = 0.06f)

    Pressable(
        modifier = modifier
            .heightIn(min = 96.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(colors.white)
            .border(BorderStroke(borderWidth, borderColor), RoundedCornerShape(13.dp)),
        onClick = onClick,
    ) {
        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(9.dp),
        ) {
            if (icon != null) {
                Box(
                    modifier = Modifier
                        .size(26.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (selected) colors.onyx else colors.fog),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        icon,
                        contentDescription = null,
                        tint = if (selected) colors.white else colors.graphite,
                        modifier = Modifier.size(14.dp),
                    )
                }
                Spacer(Modifier.height(7.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    title,
                    style = RdFontStyle.Footnote.toTextStyle().copy(fontSize = 12.5.sp, lineHeight = 15.sp),
                    color = colors.onyx,
                    maxLines = 1,
                )
                if (subtitle != null) {
                    Text(
                        subtitle,
                        style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 10.5.sp, lineHeight = 13.sp),
                        color = colors.slate,
                        // iOS scales this single line down. Compose has no equivalent minimum
                        // scale factor here, so allow a second line at larger Android font sizes
                        // instead of silently clipping localized sector descriptions.
                        maxLines = 2,
                    )
                }
            }
        }
        if (selected) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(18.dp)
                    .clip(CircleShape)
                    .background(colors.onyx),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.white, modifier = Modifier.size(10.dp))
            }
        }
    }
}

// ---- RdFooter (OBFooter) -------------------------------------------------------------------

/** Mirrors OBFooter: bottom action container, 24dp horizontal / 12dp top / 28dp bottom padding. */
@Composable
fun RdFooter(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = RdSpacing.xl, end = RdSpacing.xl, top = RdSpacing.sm, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(RdSpacing.sm),
        content = content,
    )
}

// ---- RdSelectionCounter (OBSelectionCounter) -----------------------------------------------

/** Mirrors OBSelectionCounter: checkmark icon + count + suffix label, only rendered when
 * [count] > 0. The Swift version's pulse-on-change animation isn't ported (see file doc
 * comment). */
@Composable
fun RdSelectionCounter(count: Int, suffix: String, modifier: Modifier = Modifier) {
    if (count <= 0) return
    val colors = RdTheme.colors
    Row(
        modifier = modifier.padding(vertical = RdSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Filled.Check,
            contentDescription = null,
            tint = colors.slate,
            modifier = Modifier.size(14.dp),
        )
        Spacer(Modifier.width(4.dp))
        Text(text = "$count", style = RdFontStyle.Footnote.toTextStyle(), color = colors.onyx)
        Spacer(Modifier.width(4.dp))
        Text(text = suffix, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
    }
}

// ---- Shared screen scaffold pieces (not 1:1 iOS components, but repeated across screens) ----

@Composable
fun RdOnboardingTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = RdFontStyle.Title2.toTextStyle(),
        color = RdTheme.colors.onyx,
        textAlign = TextAlign.Center,
        modifier = modifier,
    )
}

@Composable
fun RdOnboardingSubtitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = RdFontStyle.Subheadline.toTextStyle(),
        color = RdTheme.colors.slate,
        textAlign = TextAlign.Center,
        modifier = modifier,
    )
}
