package com.riskdetectedan.feature.onboarding

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.StartOffsetType
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import kotlinx.coroutines.delay

/**
 * Port of OBLoadingView.swift (2026-08-08 visual pass, Faz E) — same real ~4.9s staged sequence
 * as iOS (`runSequence`'s `DispatchQueue` timers, ported via a `LaunchedEffect` + `delay` chain),
 * not the previous flat "spinner + 2s" stand-in. Step lines now reference the user's real
 * sector/hazards/certificate labels (mirrors `state.primarySectorLabel`/`hazardsLabel`/
 * `certificateLabel`) instead of generic text. Loader now has iOS's two staggered expanding-ring
 * pulses too (2026-08-09 animation pass — previously two static faint rings under just the
 * rotating arc): each ring scales up while fading out on its own `infiniteRepeatable`, the
 * second offset via `StartOffset` so they pulse staggered, not in lockstep, same real "radar
 * pulse" cadence as iOS's paired `DispatchQueue` timers.
 */
@Composable
fun OBLoadingScreen(
    onFinished: () -> Unit,
    primarySectorLabel: String = "İnşaat",
    hazardsLabel: String = "Çok Tehlikeli",
    certificateLabel: String = "A Sınıfı",
) {
    val colors = RdTheme.colors
    var title by remember { mutableStateOf("Sana özel kurulum hazırlanıyor…") }
    var revealed by remember { mutableStateOf(BooleanArray(3)) }
    var done by remember { mutableStateOf(BooleanArray(3)) }

    LaunchedEffect(Unit) {
        delay(400); revealed = revealed.copyOf().also { it[0] = true }
        delay(700); revealed = revealed.copyOf().also { it[1] = true }
        delay(700); revealed = revealed.copyOf().also { it[2] = true }
        delay(100); done = done.copyOf().also { it[0] = true }
        delay(900); done = done.copyOf().also { it[1] = true }
        delay(900); done = done.copyOf().also { it[2] = true }
        delay(300); title = "Plan hazır."
        delay(850); onFinished()
    }

    Box(modifier = Modifier.fillMaxSize().background(colors.paper), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(horizontal = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Loader()

            Spacer(Modifier.height(32.dp))
            Text(title, style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)

            Spacer(Modifier.height(28.dp))
            Column(verticalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.widthIn(max = 320.dp)) {
                StepRow(done = done.getOrElse(0) { false }, revealed = revealed.getOrElse(0) { false }, highlight = primarySectorLabel, suffix = " için risk analiz şablonları yükleniyor...")
                StepRow(done = done.getOrElse(1) { false }, revealed = revealed.getOrElse(1) { false }, highlight = hazardsLabel, suffix = " sınıfı için kontrol listesi hazırlanıyor...")
                StepRow(done = done.getOrElse(2) { false }, revealed = revealed.getOrElse(2) { false }, highlight = certificateLabel, suffix = " için rapor formatı kişiselleştiriliyor...")
            }
        }
    }
}

@Composable
private fun Loader() {
    val colors = RdTheme.colors
    val transition = rememberInfiniteTransition(label = "loading-arc")
    val rotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(1400, easing = LinearEasing), repeatMode = RepeatMode.Restart),
        label = "loading-arc-rotation",
    )
    val pulse1 by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1800, easing = LinearEasing), repeatMode = RepeatMode.Restart),
        label = "loading-pulse-1",
    )
    val pulse2 by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            tween(1800, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
            initialStartOffset = StartOffset(900, StartOffsetType.FastForward),
        ),
        label = "loading-pulse-2",
    )

    Box(modifier = Modifier.size(112.dp), contentAlignment = Alignment.Center) {
        PulseRing(colors.onyx, pulse1)
        PulseRing(colors.onyx, pulse2)
        Box(
            modifier = Modifier.size(112.dp).clip(CircleShape).border(1.5.dp, colors.onyx.copy(alpha = 0.07f), CircleShape),
        )
        Box(
            modifier = Modifier.size(84.dp).clip(CircleShape).border(1.5.dp, colors.onyx.copy(alpha = 0.04f), CircleShape),
        )
        Box(
            modifier = Modifier
                .size(84.dp)
                .rotate(rotation)
                .border(2.dp, SolidColor(colors.onyx), CircleShape),
        )
        Box(
            modifier = Modifier.size(48.dp).clip(CircleShape).background(colors.onyx),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Description, contentDescription = null, tint = colors.white, modifier = Modifier.size(20.dp))
        }
    }
}

/** One radar-style expanding/fading ring — [progress] runs 0..1 once per loop, scale grows
 * 0.72x..1x while alpha fades to 0, so the ring appears to expand outward and vanish. */
@Composable
private fun PulseRing(color: Color, progress: Float) {
    Box(
        modifier = Modifier
            .size(84.dp)
            .graphicsLayer {
                val scale = 0.72f + 0.28f * progress
                scaleX = scale
                scaleY = scale
                alpha = (1f - progress) * 0.35f
            }
            .clip(CircleShape)
            .border(1.5.dp, color, CircleShape),
    )
}

@Composable
private fun StepRow(done: Boolean, revealed: Boolean, highlight: String, suffix: String) {
    val colors = RdTheme.colors
    if (!revealed) return
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(if (done) colors.green else colors.onyx.copy(alpha = 0.06f)),
            contentAlignment = Alignment.Center,
        ) {
            if (done) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.white, modifier = Modifier.size(11.dp))
            } else {
                Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(colors.slate.copy(alpha = 0.8f)))
            }
        }
        Spacer(Modifier.width(12.dp))
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(color = colors.onyx, fontWeight = FontWeight.SemiBold)) { append(highlight) }
                withStyle(SpanStyle(color = if (done) colors.onyx else colors.slate)) { append(suffix) }
            },
            style = RdFontStyle.Footnote.toTextStyle(),
        )
    }
}
