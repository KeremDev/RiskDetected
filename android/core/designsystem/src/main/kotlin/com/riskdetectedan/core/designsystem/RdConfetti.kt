package com.riskdetectedan.core.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.lerp
import kotlinx.coroutines.delay

/** Real (not decorative-only) Compose confetti burst — originally built for
 * `ProfessionalProgressCelebrationSheet.swift`'s celebration moment (8 pieces, per-piece
 * delay/color/rotation lifted from the Swift `ConfettiPiece` literals) and shared here
 * (2026-08-09 animation pass) for `OBPlanSummaryScreen`'s "plan ready" reveal — the same
 * "real one-shot burst on reveal" moment, not a screen-specific rebuild. */
private data class RdConfettiPiece(
    val x: Float,
    val startY: Float,
    val endYFraction: Float,
    val delayMs: Long,
    val width: Dp,
    val height: Dp,
    val color: Color,
    val rotation: Float,
)

@Composable
fun RdConfettiView(
    isActive: Boolean,
    modifier: Modifier = Modifier,
    dense: Boolean = false,
    durationMillis: Int = 620,
) {
    val colors = RdTheme.colors
    val pieces = remember(colors, dense) {
        val palette = listOf(colors.green, colors.planPlus, colors.medium, colors.greenDark, colors.low, colors.high)
        val count = if (dense) 44 else 8
        List(count) { index ->
            RdConfettiPiece(
                x = ((index * 37) % 97 + 2) / 100f,
                startY = -18f - ((index * 17) % 82),
                endYFraction = 0.82f + ((index * 13) % 22) / 100f,
                delayMs = if (dense) ((index * 67) % 900).toLong() else ((index * 37) % 140).toLong(),
                width = (5 + (index * 3) % 8).dp,
                height = (7 + (index * 5) % 12).dp,
                color = palette[index % palette.size],
                rotation = if (index % 2 == 0) 210f + index * 17f else -190f - index * 13f,
            )
        }
    }

    BoxWithConstraints(modifier = modifier) {
        val widthPx = constraints.maxWidth.toFloat()
        val heightPx = constraints.maxHeight.toFloat()
        pieces.forEachIndexed { index, piece ->
            key(index) {
                val progress = remember { Animatable(0f) }
                LaunchedEffect(isActive) {
                    if (isActive) {
                        delay(100 + piece.delayMs)
                        progress.animateTo(1f, animationSpec = tween(durationMillis = durationMillis))
                    } else {
                        progress.snapTo(0f)
                    }
                }
                val y = lerp(piece.startY, heightPx * piece.endYFraction, progress.value)
                Box(
                    modifier = Modifier
                        .offset { IntOffset((widthPx * piece.x).toInt(), y.toInt()) }
                        .size(piece.width, piece.height)
                        .graphicsLayer {
                            rotationZ = piece.rotation * progress.value
                            alpha = progress.value * 0.92f
                            val scale = 0.72f + 0.28f * progress.value
                            scaleX = scale
                            scaleY = scale
                        }
                        .clip(RoundedCornerShape(2.dp))
                        .background(piece.color),
                )
            }
        }
    }
}
