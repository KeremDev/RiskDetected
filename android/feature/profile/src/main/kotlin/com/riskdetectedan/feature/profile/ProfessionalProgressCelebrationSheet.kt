package com.riskdetectedan.feature.profile

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
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
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.lerp
import com.riskdetectedan.core.data.progress.ProfessionalProgressBadge
import com.riskdetectedan.core.designsystem.RdButtonStyle
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
 * `markBadgeSeen` + refresh pair exactly (see [ProfileScreen]'s wiring). Confetti burst kept as a
 * real (not decorative-only) Compose animation — 8 pieces, per-piece delay/color/rotation lifted
 * straight from the Swift `ConfettiPiece` literals — rather than the SwiftUI-specific
 * `.spring().delay()` modifier chain it can't share verbatim.
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
        ConfettiView(
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
                Text("Tebrikler", style = RdFontStyle.Footnote.toTextStyle(), color = colors.greenDark)
            }
            Spacer(Modifier.height(9.dp))
            Text(badge.title, style = RdFontStyle.Title2.toTextStyle(), color = colors.black, textAlign = TextAlign.Center)
            Spacer(Modifier.height(9.dp))
            Text(badge.subtitle, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
            Spacer(Modifier.height(RdSpacing.sm))
            RdPrimaryButton(text = "Tamam", onClick = onClose, style = RdButtonStyle.Green, showArrow = false)
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
            Icon(Icons.Filled.Close, contentDescription = "Kapat", tint = colors.black, modifier = Modifier.size(14.dp))
        }
    }
}

private data class ConfettiPiece(
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
private fun ConfettiView(isActive: Boolean, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    val pieces = remember(colors) {
        listOf(
            ConfettiPiece(0.10f, -20f, 76f, 0L, 6.dp, 14.dp, colors.green, 92f),
            ConfettiPiece(0.20f, -36f, 108f, 50L, 8.dp, 8.dp, colors.planPlus, -140f),
            ConfettiPiece(0.32f, -26f, 70f, 80L, 5.dp, 13.dp, colors.medium, 120f),
            ConfettiPiece(0.44f, -44f, 118f, 20L, 7.dp, 12.dp, colors.greenDark, -98f),
            ConfettiPiece(0.57f, -24f, 86f, 110L, 7.dp, 7.dp, colors.low, 170f),
            ConfettiPiece(0.68f, -38f, 104f, 60L, 5.dp, 14.dp, colors.high, -126f),
            ConfettiPiece(0.79f, -18f, 74f, 130L, 9.dp, 9.dp, colors.planPlus, 104f),
            ConfettiPiece(0.90f, -34f, 112f, 40L, 6.dp, 13.dp, colors.green, -152f),
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
