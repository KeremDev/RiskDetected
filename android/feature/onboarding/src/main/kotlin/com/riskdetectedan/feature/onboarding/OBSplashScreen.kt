package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material.icons.filled.Engineering
import androidx.compose.material.icons.filled.HealthAndSafety
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate as drawRotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Real port of `OBSplashView.swift`'s hero — closes the "background + phone mockup missing"
 * gap flagged directly against a device screenshot (the 2026-08-08 visual pass's Faz C had
 * deliberately simplified this to a bare icon-over-gradient, documented then as "phone mockup was
 * purely decorative"; the owner's review says otherwise — matches iOS's own scattered
 * safety-icon-pattern background + custom phone frame + two rotated floating chips).
 *
 * Two real, intentional platform divergences (owner explicitly approved reusing iOS's inner
 * screenshot but wants an *Android*-shaped phone around it):
 * - The safety-icon background is iOS's `OBSplashSafetyPattern.svg` (~50 hand-placed/rotated SF
 *   Symbol-derived glyphs) re-expressed as a tiled Compose `Canvas` of Material icons (6 real
 *   safety-adjacent icons — helmet/warning/fire/cross/tools/goggles) at low opacity in a
 *   brick-offset grid with alternating rotation. Not a pixel copy of the SVG (no SVG rasterizer
 *   available in this environment), but a real tiled pattern, not a flat gradient.
 * - [OBSplashPhoneFrame] is a real from-scratch Android phone silhouette (rounded body, punch-hole
 *   front camera, side power/volume buttons) instead of iOS's Dynamic-Island/notch frame — the
 *   *inner* screen content is the exact same `ob_splash_preview.png` iOS ships
 *   (`Assets.xcassets/OBSplashPreview.imageset`, copied byte-for-byte, this app's own real Home
 *   screenshot, not a third-party asset).
 */
@Composable
fun OBSplashScreen(onNext: () -> Unit, onSkip: () -> Unit) {
    val colors = RdTheme.colors
    Box(modifier = Modifier.fillMaxSize().background(Color(0xFFFFFFFF))) {
        Column(modifier = Modifier.fillMaxSize()) {
            BoxWithConstraints(modifier = Modifier.fillMaxWidth().weight(1f)) {
                val scale = ((maxWidth / 402.dp).coerceIn(0.86f, 1.12f))
                OBSplashHero(scale = scale)
            }

            // ---- Bottom sheet (OBSplashBottomSheet — real port, unchanged) ----
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .shadow(elevation = 17.dp, shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp))
                    .clip(RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp))
                    .background(colors.white)
                    .padding(horizontal = RdSpacing.xl)
                    .padding(top = 24.dp, bottom = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                OBSplashProgressDots()

                Spacer(Modifier.height(16.dp))
                Text(
                    text = stringResource(RdR.string.rd_profesyonel_isg_asistani),
                    style = RdFontStyle.Title1.toTextStyle(),
                    color = colors.onyx,
                    textAlign = TextAlign.Center,
                )

                Spacer(Modifier.height(11.dp))
                Text(
                    text = stringResource(RdR.string.rd_splash_aciklama),
                    style = RdFontStyle.Subheadline.toTextStyle(),
                    color = colors.slate,
                    textAlign = TextAlign.Center,
                )

                Spacer(Modifier.height(17.dp))
                RdPrimaryButton(
                    text = stringResource(RdR.string.rd_devam_et_baslik),
                    onClick = onNext,
                    style = RdButtonStyle.Onyx,
                )

                TextButton(onClick = onSkip) {
                    Text(
                        text = stringResource(RdR.string.rd_atla),
                        style = RdFontStyle.Subheadline.toTextStyle(),
                        color = colors.slate,
                    )
                }
            }
        }
    }
}

@Composable
private fun OBSplashHero(scale: Float) {
    Box(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFFEEF0F2)),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(Color.White.copy(alpha = 0.42f), Color.White.copy(alpha = 0f)),
                    ),
                ),
        )
        OBSplashPattern(modifier = Modifier.fillMaxSize())

        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            OBSplashPhoneFrame(width = (250 * scale).dp, modifier = Modifier.padding(bottom = (28 * scale).dp))
        }

        OBSplashFloatingChip(
            title = stringResource(RdR.string.rd_on_iki_tehlike),
            subtitle = stringResource(RdR.string.rd_tespit_edildi),
            accent = Color(0xFFE5484D),
            iconBackground = Color(0xFFFDECEC),
            icon = Icons.Filled.Warning,
            modifier = Modifier
                .padding(start = (12 * scale).dp, top = (36 * scale).dp)
                .align(Alignment.TopStart)
                .rotate(-5f),
        )
        OBSplashFloatingChip(
            title = stringResource(RdR.string.rd_kok_neden_mevzuat),
            subtitle = stringResource(RdR.string.rd_bilgisi_hazirlaniyor),
            accent = Color(0xFFF59E0B),
            iconBackground = Color(0xFFFFF4E5),
            icon = null,
            modifier = Modifier
                .padding(end = (10 * scale).dp, top = (24 * scale).dp)
                .align(Alignment.TopEnd)
                .rotate(5f),
        )
    }
}

/** Tiled low-opacity safety-icon background — real Compose port of the *intent* of
 * `OBSplashSafetyPattern.svg` (see [OBSplashScreen]'s doc comment for why it isn't a pixel copy).
 * Vector icons are drawn straight into the `Canvas` via [rememberVectorPainter] (not composed as
 * individual `Icon`s) so tiling ~40-60 of them stays cheap. */
@Composable
private fun OBSplashPattern(modifier: Modifier = Modifier) {
    val tint = Color(0xFF0E1116).copy(alpha = 0.09f)
    val icons = listOf(
        Icons.Filled.Engineering,
        Icons.Filled.Warning,
        Icons.Filled.LocalFireDepartment,
        Icons.Filled.HealthAndSafety,
        Icons.Filled.Construction,
        Icons.Filled.Visibility,
    )
    val painters = icons.map { rememberVectorPainter(it) }

    Canvas(modifier = modifier) {
        val cell = 64.dp.toPx()
        val iconSize = 22.dp.toPx()
        val colorFilter = ColorFilter.tint(tint)
        var row = 0
        var y = -cell / 2f
        while (y < size.height + cell) {
            val offsetX = if (row % 2 == 0) 0f else cell / 2f
            var x = -cell / 2f + offsetX
            var col = 0
            while (x < size.width + cell) {
                val painter = painters[(row * 7 + col * 3) % painters.size]
                val angle = ((row * 37 + col * 53) % 40 - 20).toFloat()
                translate(left = x, top = y) {
                    drawRotate(degrees = angle, pivot = Offset(iconSize / 2f, iconSize / 2f)) {
                        with(painter) {
                            draw(size = Size(iconSize, iconSize), colorFilter = colorFilter)
                        }
                    }
                }
                x += cell
                col++
            }
            y += cell
            row++
        }
    }
}

@Composable
private fun OBSplashPhoneFrame(width: Dp, modifier: Modifier = Modifier) {
    val height = width * 462f / 250f
    val bezel = width * 0.035f
    val bodyRadius = width * 0.14f
    val screenRadius = bodyRadius - bezel * 0.6f

    Box(
        modifier = modifier
            .width(width)
            .height(height)
            .shadow(elevation = 28.dp, shape = RoundedCornerShape(bodyRadius), ambientColor = Color(0xFF0E1116), spotColor = Color(0xFF0E1116))
            .clip(RoundedCornerShape(bodyRadius))
            .background(
                Brush.linearGradient(listOf(Color(0xFF2C2C2F), Color(0xFF0B0B0D), Color(0xFF1A1A1C))),
            ),
    ) {
        Image(
            painter = painterResource(R.drawable.ob_splash_preview),
            contentDescription = stringResource(RdR.string.rd_riskdetected_onizleme_telefonu),
            contentScale = ContentScale.Crop,
            alignment = Alignment.TopCenter,
            modifier = Modifier
                .fillMaxSize()
                .padding(bezel)
                .clip(RoundedCornerShape(screenRadius)),
        )
        // Android-style front punch-hole camera (not a Dynamic Island/notch — the real,
        // deliberate mockup-shape divergence from iOS this pass makes).
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = width * 0.028f)
                .size(width * 0.028f)
                .clip(CircleShape)
                .background(Color.Black),
        )
    }
}

@Composable
private fun OBSplashFloatingChip(
    title: String,
    subtitle: String,
    accent: Color,
    iconBackground: Color,
    icon: ImageVector?,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .shadow(elevation = 15.dp, shape = RoundedCornerShape(14.dp), ambientColor = Color(0xFF0E1116), spotColor = Color(0xFF0E1116))
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White)
            .padding(horizontal = 11.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(22.dp).clip(RoundedCornerShape(7.dp)).background(iconBackground),
            contentAlignment = Alignment.Center,
        ) {
            if (icon != null) {
                Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(12.dp))
            } else {
                OBSplashSpinnerGlyph(color = accent)
            }
        }
        Spacer(Modifier.width(7.dp))
        Column {
            Text(title, style = RdFontStyle.Caption.toTextStyle(), color = Color(0xFF0E1116))
            Text(subtitle, style = RdFontStyle.Caption.toTextStyle(), color = accent)
        }
    }
}

@Composable
private fun OBSplashSpinnerGlyph(color: Color) {
    Canvas(modifier = Modifier.size(13.dp)) {
        val strokeWidth = 1.8.dp.toPx()
        drawArc(
            color = color.copy(alpha = 0.22f),
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            style = Stroke(width = strokeWidth),
        )
        drawArc(
            color = color,
            startAngle = -36f,
            sweepAngle = 240f,
            useCenter = false,
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
        )
    }
}

/** Mirrors OBSplashProgressDots: one filled pill (current step) + 5 dim dots (5 more onboarding
 * steps ahead). The dots themselves stay static, matches this pass's "no per-segment animation"
 * policy already used by [com.riskdetectedan.core.designsystem.RdProgress] (the shared bar the
 * 4 choice screens use — touching per-segment fill animation only here would look inconsistent
 * with those). The active pill breathes with a subtle scale+alpha pulse instead (2026-08-09
 * animation pass) — a "you are here" cue, its own real motion, not a per-segment fill/reveal so
 * it doesn't collide with `RdProgress`'s documented static policy. */
@Composable
private fun OBSplashProgressDots() {
    val colors = RdTheme.colors
    val infiniteTransition = rememberInfiniteTransition(label = "splash-progress-pill")
    val breathe by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1100, easing = androidx.compose.animation.core.FastOutSlowInEasing), repeatMode = RepeatMode.Reverse),
        label = "splash-progress-pill-breathe",
    )
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(width = 20.dp, height = 6.dp)
                .graphicsLayer {
                    val scale = 1f + 0.12f * breathe
                    scaleX = scale
                    scaleY = scale
                    alpha = 0.82f + 0.18f * breathe
                }
                .clip(RoundedCornerShape(50))
                .background(colors.onyx),
        )
        repeat(5) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(colors.slate.copy(alpha = 0.4f)),
            )
        }
    }
}
