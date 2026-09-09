package com.riskdetectedan.core.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
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
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/** Shared Compose confetti system. Its default behavior preserves the compact one-shot burst
 * originally built for `ProfessionalProgressCelebrationSheet.swift`; [RdConfettiView]'s optional
 * top-down flow mode adds staggered, continuously recycled pieces that fade before reaching the
 * bottom for longer celebrations such as `OBPlanSummaryScreen`. */
private data class RdConfettiPiece(
    val x: Float,
    val startY: Float,
    val endYFraction: Float,
    val delayMs: Long,
    val width: Dp,
    val height: Dp,
    val color: Color,
    val rotation: Float,
    val driftFraction: Float,
    val durationScale: Float,
)

/**
 * Optional deterministic clock used by screenshot tests. Production leaves this null and keeps
 * the real coroutine-driven animation; tests can provide elapsed time since activation so every
 * particle is rendered at the same frame on every host.
 */
val LocalRdConfettiSnapshotElapsedMillis = staticCompositionLocalOf<Long?> { null }

@Composable
fun RdConfettiView(
    isActive: Boolean,
    modifier: Modifier = Modifier,
    dense: Boolean = false,
    durationMillis: Int = 620,
    flowFromTop: Boolean = false,
) {
    val colors = RdTheme.colors
    val snapshotElapsedMillis = LocalRdConfettiSnapshotElapsedMillis.current
    val pieces = remember(colors, dense, flowFromTop) {
        val palette = listOf(colors.green, colors.planPlus, colors.medium, colors.greenDark, colors.low, colors.high)
        val count = when {
            flowFromTop && dense -> 32
            flowFromTop -> 18
            dense -> 44
            else -> 8
        }
        List(count) { index ->
            RdConfettiPiece(
                x = ((index * 37) % 97 + 2) / 100f,
                startY = if (flowFromTop) -22f - ((index * 23) % 118) else -18f - ((index * 17) % 82),
                endYFraction = if (flowFromTop) 1.0f + ((index * 13) % 3) / 100f else 0.82f + ((index * 13) % 22) / 100f,
                delayMs = when {
                    flowFromTop -> ((index * 193) % 4_600).toLong()
                    dense -> ((index * 67) % 900).toLong()
                    else -> ((index * 37) % 140).toLong()
                },
                width = (if (flowFromTop) 4 + (index * 3) % 6 else 5 + (index * 3) % 8).dp,
                height = (if (flowFromTop) 6 + (index * 5) % 9 else 7 + (index * 5) % 12).dp,
                color = palette[index % palette.size],
                rotation = if (index % 2 == 0) 210f + index * 17f else -190f - index * 13f,
                driftFraction = if (flowFromTop) (((index * 29) % 81) - 40) / 1_000f else 0f,
                durationScale = if (flowFromTop) 0.88f + ((index * 11) % 29) / 100f else 1f,
            )
        }
    }

    BoxWithConstraints(modifier = modifier) {
        val widthPx = constraints.maxWidth.toFloat()
        val heightPx = constraints.maxHeight.toFloat()
        pieces.forEachIndexed { index, piece ->
            key(index) {
                val progress = remember { Animatable(0f) }
                val pieceDurationMillis = (durationMillis * piece.durationScale).roundToInt().coerceAtLeast(1)
                LaunchedEffect(isActive, snapshotElapsedMillis, flowFromTop) {
                    if (isActive && snapshotElapsedMillis == null) {
                        progress.snapTo(0f)
                        delay(100 + piece.delayMs)
                        if (flowFromTop) {
                            while (true) {
                                progress.snapTo(0f)
                                progress.animateTo(
                                    1f,
                                    animationSpec = tween(
                                        durationMillis = pieceDurationMillis,
                                        easing = LinearEasing,
                                    ),
                                )
                            }
                        } else {
                            progress.animateTo(1f, animationSpec = tween(durationMillis = durationMillis))
                        }
                    } else {
                        progress.snapTo(0f)
                    }
                }
                // A supplied snapshot time is an explicit test frame and must not race the
                // screen's separate activation coroutine while Roborazzi is capturing.
                val progressValue = if (snapshotElapsedMillis != null) {
                    val elapsed = snapshotElapsedMillis - 100L - piece.delayMs
                    val rawProgress = if (flowFromTop) {
                        if (elapsed <= 0L) 0f else (elapsed % pieceDurationMillis).toFloat() / pieceDurationMillis
                    } else {
                        (elapsed.toFloat() / durationMillis).coerceIn(0f, 1f)
                    }
                    if (flowFromTop) rawProgress else FastOutSlowInEasing.transform(rawProgress)
                } else {
                    progress.value
                }
                val y = lerp(piece.startY, heightPx * piece.endYFraction, progressValue)
                val sway = if (flowFromTop) {
                    sin((progressValue * PI * 2.0) + (index * 0.73)).toFloat() * widthPx * 0.018f
                } else {
                    0f
                }
                val x = (widthPx * piece.x) + (widthPx * piece.driftFraction * progressValue) + sway
                val particleAlpha = if (flowFromTop) {
                    val fadeIn = (progressValue / 0.07f).coerceIn(0f, 1f)
                    val fadeOut = ((1f - progressValue) / 0.22f).coerceIn(0f, 1f)
                    minOf(fadeIn, fadeOut) * 0.9f
                } else if (snapshotElapsedMillis == null) {
                    progressValue * 0.92f
                } else if (progressValue > 0f) {
                    0.92f
                } else {
                    0f
                }
                Box(
                    modifier = Modifier
                        .offset { IntOffset(x.toInt(), y.toInt()) }
                        .size(piece.width, piece.height)
                        .graphicsLayer {
                            // Skia's anti-aliasing for arbitrary rotations differs by a pixel
                            // between macOS and Linux. Snapshot tests keep the particle layout
                            // and colors, but use an axis-aligned frame so exact goldens remain
                            // portable across developer machines and CI runners.
                            rotationZ = if (snapshotElapsedMillis == null) {
                                piece.rotation * progressValue
                            } else {
                                0f
                            }
                            alpha = particleAlpha
                            val scale = if (snapshotElapsedMillis == null) {
                                0.72f + 0.28f * progressValue
                            } else {
                                1f
                            }
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
