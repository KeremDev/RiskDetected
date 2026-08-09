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
    val endY: Float,
    val delayMs: Long,
    val width: Dp,
    val height: Dp,
    val color: Color,
    val rotation: Float,
)

@Composable
fun RdConfettiView(isActive: Boolean, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    val pieces = remember(colors) {
        listOf(
            RdConfettiPiece(0.10f, -20f, 76f, 0L, 6.dp, 14.dp, colors.green, 92f),
            RdConfettiPiece(0.20f, -36f, 108f, 50L, 8.dp, 8.dp, colors.planPlus, -140f),
            RdConfettiPiece(0.32f, -26f, 70f, 80L, 5.dp, 13.dp, colors.medium, 120f),
            RdConfettiPiece(0.44f, -44f, 118f, 20L, 7.dp, 12.dp, colors.greenDark, -98f),
            RdConfettiPiece(0.57f, -24f, 86f, 110L, 7.dp, 7.dp, colors.low, 170f),
            RdConfettiPiece(0.68f, -38f, 104f, 60L, 5.dp, 14.dp, colors.high, -126f),
            RdConfettiPiece(0.79f, -18f, 74f, 130L, 9.dp, 9.dp, colors.planPlus, 104f),
            RdConfettiPiece(0.90f, -34f, 112f, 40L, 6.dp, 13.dp, colors.green, -152f),
        )
    }

    BoxWithConstraints(modifier = modifier) {
        val widthPx = constraints.maxWidth.toFloat()
        pieces.forEachIndexed { index, piece ->
            key(index) {
                val progress = remember { Animatable(0f) }
                LaunchedEffect(isActive) {
                    if (isActive) {
                        delay(100 + piece.delayMs)
                        progress.animateTo(1f, animationSpec = tween(durationMillis = 620))
                    } else {
                        progress.snapTo(0f)
                    }
                }
                val y = lerp(piece.startY, piece.endY, progress.value)
                Box(
                    modifier = Modifier
                        .offset { IntOffset((widthPx * piece.x).toInt(), y.dp.roundToPx()) }
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
