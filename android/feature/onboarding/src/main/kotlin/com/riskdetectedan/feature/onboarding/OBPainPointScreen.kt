package com.riskdetectedan.feature.onboarding

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdFooter
import com.riskdetectedan.core.designsystem.RdHeroTile
import com.riskdetectedan.core.designsystem.RdHeroTint
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.RdTopBar
import com.riskdetectedan.core.designsystem.toTextStyle
import kotlinx.coroutines.delay

private data class PainItem(val icon: ImageVector, val text: String)

private val pains = listOf(
    PainItem(Icons.Filled.Schedule, "Saatlerce süren rapor yazımı."),
    PainItem(Icons.Filled.PhotoLibrary, "Dağınık fotoğraflar ve notlar."),
    PainItem(Icons.Filled.EventBusy, "Geç teslim edilen değerlendirmeler."),
)

/** Port of OBPainPointView.swift (2026-08-08 visual pass, Faz E). Hero simplified from iOS's
 * layered moon+document SF Symbols to a single document icon (documented per this pass's policy,
 * no custom multi-layer icon composition). Real ported behavior: pain cards check themselves in
 * sequentially ~0.6-1.5s after the screen appears (mirrors `runCheckSequence`'s staggered
 * `DispatchQueue` timers via a Compose `LaunchedEffect` + `delay` loop — a real feature, not a
 * decoration, worth keeping). The "Bunu **birlikte** değiştireceğiz." mirror banner is ported as
 * a dark card with a real diagonal shimmer sweep (2026-08-09 animation pass — was a static card
 * before, matching iOS's repeating `DispatchQueue`-driven sweep with an `infiniteTransition`
 * instead). `RdTopBar`'s "01 / 05" numbering is real and intentionally
 * different from the choice screens' separate "01-04 / 04" counter — iOS itself has two
 * back-to-back progress indicators here, not a bug to reconcile. */
@Composable
fun OBPainPointScreen(onNext: () -> Unit) {
    val colors = RdTheme.colors
    var checked by remember { mutableStateOf(BooleanArray(pains.size)) }

    LaunchedEffect(Unit) {
        val state = checked.copyOf()
        for (i in pains.indices) {
            delay(if (i == 0) 600L else 450L)
            state[i] = true
            checked = state.copyOf()
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdTopBar(step = 1, total = 5)

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            RdHeroTile(tint = RdHeroTint.Dusk) {
                Icon(Icons.Filled.Description, contentDescription = null, tint = Color(0xFFF8F7F3), modifier = Modifier.size(36.dp))
            }

            Spacer(Modifier.height(16.dp))
            Text(
                "Sahada gördüklerini akşam ofiste mi yazıyorsun?",
                style = RdFontStyle.Title2.toTextStyle(),
                color = colors.onyx,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(6.dp))
            Text("Tanıdık geliyor mu?", style = RdFontStyle.Subheadline.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)

            Spacer(Modifier.height(18.dp))
            HorizontalDivider(color = colors.line)

            Spacer(Modifier.height(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                pains.forEachIndexed { index, pain ->
                    PainCard(pain = pain, isChecked = checked.getOrElse(index) { false })
                }
            }

            Spacer(Modifier.height(8.dp))
            MirrorBanner()
            Spacer(Modifier.height(16.dp))
        }

        RdFooter {
            RdPrimaryButton(text = "Devam", onClick = onNext, style = RdButtonStyle.Onyx)
        }
    }
}

@Composable
private fun PainCard(pain: PainItem, isChecked: Boolean) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(pain.icon, contentDescription = null, tint = colors.onyx, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Text(pain.text, style = RdFontStyle.Footnote.toTextStyle(), color = colors.onyx, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape)
                .background(if (isChecked) colors.green else Color.Transparent)
                .border(1.5.dp, if (isChecked) Color.Transparent else colors.onyx.copy(alpha = 0.18f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (isChecked) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.white, modifier = Modifier.size(12.dp))
            }
        }
    }
}

@Composable
private fun MirrorBanner() {
    val colors = RdTheme.colors
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(
                Brush.radialGradient(
                    colors = listOf(colors.green.copy(alpha = 0.22f), colors.onyx),
                    center = Offset(1f, 0f),
                    radius = 500f,
                ),
            ),
    ) {
        val bannerWidthPx = constraints.maxWidth.toFloat()
        val infiniteTransition = rememberInfiniteTransition(label = "shimmer")
        // Diagonal shimmer sweep — real port of iOS's repeating DispatchQueue-driven sweep, same
        // mechanism as everywhere else in this pass: an infiniteTransition drives a translation,
        // not a decorative one-shot. Sweeps left-to-right every 2.2s with a pause between passes
        // (matches a real "sheen" cadence, not a distracting continuous scroll).
        val sweep by infiniteTransition.animateFloat(
            initialValue = -0.6f,
            targetValue = 1.6f,
            animationSpec = infiniteRepeatable(
                animation = tween(2200, easing = LinearEasing),
                repeatMode = RepeatMode.Restart,
            ),
            label = "sweepOffset",
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    translationX = bannerWidthPx * sweep
                    rotationZ = 18f
                }
                .width(60.dp)
                .background(
                    Brush.linearGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color.White.copy(alpha = 0.16f),
                            Color.Transparent,
                        ),
                    ),
                ),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Bunu ", style = RdFontStyle.Callout.toTextStyle(), color = colors.white)
            Text("birlikte", style = RdFontStyle.Callout.toTextStyle(), color = Color(0xFF4FE07E))
            Text(" değiştireceğiz.", style = RdFontStyle.Callout.toTextStyle(), color = colors.white)
        }
    }
}
