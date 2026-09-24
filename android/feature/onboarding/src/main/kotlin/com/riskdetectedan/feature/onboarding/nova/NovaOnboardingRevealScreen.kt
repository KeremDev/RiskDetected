package com.riskdetectedan.feature.onboarding.nova

import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.derivedStateOf
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.unit.offset
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaReduceMotion
import com.riskdetectedan.feature.onboarding.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

// MARK: - Reveal

private val revealPage = Color(0xFFF5F7FA)
private const val REVEAL_LIST_HEIGHT = 412f

/**
 * "İSG Adasına Hoşgeldiniz" — the screen between the splash and intro 1 (iOS `NovaOBRevealScreen`,
 * `design_handoff_reveal_screen`). Module cards drift upward in an endless loop behind a white
 * sheet; one card at a time is lifted into focus.
 */
@Composable
internal fun NovaOBRevealScreen(controller: NovaOnboardingController, onLogin: () -> Unit) {
    Column(Modifier.fillMaxSize().background(revealPage)) {
        Row(Modifier.fillMaxWidth().zIndex(20f).padding(horizontal = 20.dp), horizontalArrangement = Arrangement.End) {
            ObText("Geç", 14f, Modifier.novaPress { controller.go(NovaOBScreen.Intro1) }.padding(horizontal = 6.dp, vertical = 8.dp),
                color = Color(0xFF6A7379))
        }
        RevealStage(Modifier.weight(1f).fillMaxWidth().zIndex(0f))
        RevealSheet(controller, onLogin, Modifier.zIndex(10f).layout { measurable, constraints ->
            // `margin-top: -26px`: the sheet rides over the bottom of the card stage.
            val overlap = 26.dp.roundToPx()
            val placeable = measurable.measure(constraints)
            layout(placeable.width, placeable.height - overlap) { placeable.place(0, -overlap) }
        })
    }
}

@Composable
private fun RevealSheet(controller: NovaOnboardingController, onLogin: () -> Unit, modifier: Modifier) {
    Column(modifier.fillMaxWidth()
        .drawBehind {
            // Only the top corners are rounded; the bottom ones run off screen.
            val radius = 34.dp.toPx()
            val extended = Size(size.width, size.height + radius * 3)
            drawShadowedRoundRect(Offset.Zero, extended, radius, Color.White,
                Color(0xFF142030).copy(alpha = 0.1f), blur = 44.dp.toPx(), dy = (-16).dp.toPx())
        }
        // The prototype measures 34 from the frame's bottom edge, navigation bar included.
        .padding(start = 24.dp, end = 24.dp, top = 34.dp, bottom = obPadBottom(34f)),
        horizontalAlignment = Alignment.CenterHorizontally) {
        ObText("İSG Adasına Hoşgeldiniz", 29f, Modifier.fillMaxWidth(), weight = 800, color = Color(0xFF141C24),
            tracking = -0.9f, align = TextAlign.Center)
        // `text-wrap: balance` breaks after "tüm" at the design width; the break is fixed so every
        // device shows the same two highlighter strokes.
        Column(Modifier.padding(top = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            MarkedLine("İş Güvenliğinin tüm")
            MarkedLine("süreçleri artık tek bir yerde.")
        }
        ObText("Takiplerini kolaylaştır, dokümanlarına hızla ulaş, işlerini düzenle.\nDaha az operasyon, daha fazla kontrol.",
            14.5f, Modifier.fillMaxWidth().padding(top = 10.dp), color = Color(0xFF5C6873), lineHeight = 1.6f, align = TextAlign.Center)
        RevealActions(controller, onLogin, Modifier.padding(top = 98.dp))
    }
}

@Composable
private fun MarkedLine(text: String) {
    val em = 16.5f
    ObText(text, em, Modifier.drawBehind {
        // CSS paints the background over the font's content area (≈1.26em), not the 1.4em line box.
        val halfLeading = ((1.4f - 1.26f) * em / 2).dp.toPx()
        val rect = Rect(
            left = -(0.36f * em).dp.toPx(), top = halfLeading - (0.16f * em).dp.toPx(),
            right = size.width + (0.42f * em).dp.toPx(), bottom = size.height - halfLeading + (0.2f * em).dp.toPx(),
        )
        drawMarker(rect, em.dp.toPx())
    }, weight = 700, color = Color(0xFF2A343E), lineHeight = 1.4f, tracking = -0.2f, maxLines = 1)
}

@Composable
private fun RevealActions(controller: NovaOnboardingController, onLogin: () -> Unit, modifier: Modifier) {
    val reduceMotion = rememberNovaReduceMotion()
    val raise = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val visible = remember { Animatable(if (reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (reduceMotion) return@LaunchedEffect
        // `isgPeek`: 700 ms cubic-bezier(.3,1.4,.5,1) after 350 ms; opaque by the 40% keyframe.
        delay(350)
        val peek = CubicBezierEasing(0.3f, 1.4f, 0.5f, 1f)
        launch { visible.animateTo(1f, tween(280, easing = peek)) }
        raise.animateTo(1f, tween(700, easing = peek))
    }
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
        Box {
            // Peeks over the CTA's top-left corner with its chin tucked behind the button: 80×80,
            // left −8, bottom 50 from the CTA's bottom edge, pivoting on its own bottom centre.
            Image(painterResource(R.drawable.nova_ob_mascot_peek), null, Modifier
                .offset(x = (-8).dp, y = (-70).dp)
                .size(80.dp)
                .graphicsLayer {
                    transformOrigin = TransformOrigin(0.5f, 1f)
                    translationY = (46f * (1f - raise.value)).dp.toPx()
                    rotationZ = -12f * raise.value
                    alpha = visible.value.coerceIn(0f, 1f)
                })
            ObPillButton("Başlayalım", height = 60f, fontSize = 17f, horizontalPadding = 40f) { controller.go(NovaOBScreen.Intro1) }
        }
        Spacer(Modifier.weight(1f))
        val regular = obStyle(13.5f, color = NovaOB.slate, lineHeight = 1.45f)
        val bold = obStyle(13.5f, 700)
        Text(buildAnnotatedString {
            withStyle(SpanStyle(fontFamily = regular.fontFamily, fontSize = regular.fontSize, color = NovaOB.slate)) { append("Hesabın var mı?\n") }
            withStyle(SpanStyle(fontFamily = bold.fontFamily, fontWeight = bold.fontWeight, fontSize = bold.fontSize, color = NovaOB.ink)) { append("Giriş yap") }
        }, Modifier.novaPress(onClick = onLogin), style = regular, textAlign = TextAlign.End)
    }
}

// MARK: - Card loop

/**
 * The endless card column. There is no timer: every row plays the same looping track offset by
 * `index × step` — the prototype's `isgSlotN` / `isgHaloN` phase model — so the loop never jumps
 * or restarts and the wrap happens fully transparent. Reduce Motion holds the first frame.
 *
 * The clock is read only in the layout and draw phases, and each frame's row styles and halo
 * opacities are computed once, so the loop never recomposes the rows.
 */
@Composable
private fun RevealStage(modifier: Modifier) {
    val reduceMotion = rememberNovaReduceMotion()
    val cycle = revealRows.size * REVEAL_STEP
    val clock = rememberInfiniteTransition(label = "reveal-loop")
    val running = clock.animateFloat(0f, cycle, infiniteRepeatable(tween((cycle * 1000).roundToInt(), easing = LinearEasing),
        RepeatMode.Restart), label = "reveal-clock")
    val frame = remember(reduceMotion) {
        derivedStateOf {
            val elapsed = if (reduceMotion) 0f else running.value
            RevealFrame(
                revealRows.mapIndexed { index, row -> revealStyle(revealPhase(elapsed, index, cycle), row.color) },
                revealRows.indices.map { revealHaloOpacity(revealPhase(elapsed, it, cycle)) },
            )
        }
    }
    Box(modifier) {
        Box(Modifier.fillMaxWidth().wrapContentHeight(Alignment.Top, unbounded = true).height(REVEAL_LIST_HEIGHT.dp)
            .offset(y = (-24).dp).clipToBounds().drawBehind { drawHalos(frame.value.halos) }, contentAlignment = Alignment.Center) {
            revealRows.forEachIndexed { index, row ->
                RevealRow(row) { frame.value.styles[index] }
            }
            Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(26.dp).zIndex(6f)
                .background(Brush.verticalGradient(listOf(revealPage, revealPage.copy(alpha = 0f)))))
        }
    }
}

private class RevealFrame(val styles: List<RevealRowStyle>, val halos: List<Float>)

/**
 * The tinted glow behind the active card. The prototype blurs a 380×260 oval by 60px; a radial
 * falloff with the same reach draws it without an offscreen layer, so it can never be cut into a
 * box and costs nothing per frame. It fades out before the stage's top edge.
 */
private fun DrawScope.drawHalos(opacities: List<Float>) {
    val center = Offset(size.width / 2, size.height * 0.44f)
    val radiusX = 250.dp.toPx()
    val radiusY = min(170.dp.toPx(), center.y - 4.dp.toPx())
    opacities.forEachIndexed { index, opacity ->
        if (opacity <= 0.002f) return@forEachIndexed
        val color = Color(revealRows[index].color)
        scale(1f, radiusY / radiusX, center) {
            drawCircle(Brush.radialGradient(
                0f to color.copy(alpha = opacity), 0.35f to color.copy(alpha = opacity * 0.82f),
                0.6f to color.copy(alpha = opacity * 0.45f), 0.8f to color.copy(alpha = opacity * 0.16f),
                1f to color.copy(alpha = 0f), center = center, radius = radiusX), radiusX, center)
        }
    }
}

@Composable
private fun RevealRow(row: RevealRowData, style: () -> RevealRowStyle) {
    val icon = remember(row.icon) { row.icon.split("|").map(ObSvgPath::segment) }
    Row(Modifier
        // The active card rides above its neighbours; the order changes without recomposing.
        .layout { measurable, constraints ->
            val placeable = measurable.measure(constraints)
            layout(placeable.width, placeable.height) { placeable.place(0, 0, zIndex = style().zIndex) }
        }
        .fillMaxWidth().padding(horizontal = 24.dp)
        .graphicsLayer {
            val current = style()
            translationY = current.offsetY.dp.toPx()
            scaleX = current.scale; scaleY = current.scale
            alpha = current.opacity
            // A blur needs an offscreen layer, which would cut the card's shadow and ring at its bounds;
            // it only applies while the card casts neither. Quantised so the effect is rebuilt only
            // when it visibly changes.
            val blur = (current.blur * 4).roundToInt() / 4f
            val blurred = blur > 0f && current.opacity > 0.01f && current.shadowAlpha < 0.01f && current.ring < 0.05f &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            renderEffect = if (blurred) BlurEffect(blur.dp.toPx(), blur.dp.toPx(), TileMode.Decal) else null
            // Without a blur, opacity is applied per draw call, so nothing is clipped to a box.
            compositingStrategy = if (blurred) CompositingStrategy.Auto else CompositingStrategy.ModulateAlpha
        }
        .drawBehind {
            val current = style()
            if (current.opacity <= 0.01f) return@drawBehind
            val radius = 16.dp.toPx()
            if (current.ring > 0f) {
                // `box-shadow: 0 0 0 Npx` — a solid ring outside the border box.
                val ring = current.ring.dp.toPx()
                drawRoundRect(current.ringColor.color, Offset(-ring, -ring), Size(size.width + ring * 2, size.height + ring * 2),
                    CornerRadius(radius + ring))
            }
            drawShadowedRoundRect(Offset.Zero, size, radius, current.background.color,
                Color(0xFF18263A).copy(alpha = current.shadowAlpha), current.shadowBlur.dp.toPx(), current.shadowY.dp.toPx())
            val stroke = 1.dp.toPx()
            drawRoundRect(current.border.color, Offset(stroke / 2, stroke / 2), Size(size.width - stroke, size.height - stroke),
                CornerRadius(radius - stroke / 2), style = Stroke(stroke))
        }
        .layout { measurable, constraints ->
            // Padding 16 × (12…14): the active card grows by relayout only.
            val horizontal = 16.dp.roundToPx()
            val vertical = style().verticalPadding.dp.roundToPx()
            val placeable = measurable.measure(constraints.offset(-horizontal * 2, -vertical * 2))
            layout(placeable.width + horizontal * 2, placeable.height + vertical * 2) { placeable.place(horizontal, vertical) }
        },
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.size(19.dp)) {
            val color = style().icon.color
            val factor = size.width / 24f
            scale(factor, factor, pivot = Offset.Zero) {
                icon.forEach { drawPath(it, color, style = Stroke(1.7f, cap = StrokeCap.Round, join = StrokeJoin.Round)) }
            }
        }
        Text(row.name, Modifier.weight(1f), style = obStyle(13.5f, 600, Color(0xFF1B242E)), maxLines = 1, overflow = TextOverflow.Ellipsis)
        ObText(row.meta, 12f, weight = 600, color = Color(0xFF7A848E), maxLines = 1)
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            repeat(3) { Box(Modifier.size(3.dp).background(Color(0xFFC3CAD2), CircleShape)) }
        }
    }
}

/** A filled round rect with a CSS-style drop shadow (`0 dy blur color`). */
private fun DrawScope.drawShadowedRoundRect(topLeft: Offset, size: Size, radius: Float, fill: Color, shadow: Color, blur: Float, dy: Float) {
    if (fill.alpha <= 0f && shadow.alpha <= 0f) return
    drawIntoCanvas { canvas ->
        val paint = Paint().asFrameworkPaint().apply {
            isAntiAlias = true
            color = fill.toArgb()
            if (shadow.alpha > 0f && blur > 0f) setShadowLayer(blur / 2, 0f, dy, shadow.toArgb())
        }
        canvas.nativeCanvas.drawRoundRect(topLeft.x, topLeft.y, topLeft.x + size.width, topLeft.y + size.height, radius, radius, paint)
    }
}

// MARK: - Highlighter

private class MarkerLayer(val angle: Float, val stops: List<Triple<Float, Float, Long>>, val height: Float, val position: Float)

/** `.isg-marker`: three offset, angled, translucent yellow strokes that never quite cover the text. */
private val markerLayers = listOf(
    MarkerLayer(100f, listOf(Triple(0f, 0f, 0xFFFFE496), Triple(0.34f, 0.03f, 0xFFFFE496), Triple(0.24f, 0.30f, 0xFFFFDE8C),
        Triple(0.32f, 0.52f, 0xFFFFE496), Triple(0.28f, 0.62f, 0xFFFFE496), Triple(0f, 0.66f, 0xFFFFE496)), 0.58f, 0.92f),
    MarkerLayer(96f, listOf(Triple(0f, 0.38f, 0xFFFFE292), Triple(0.26f, 0.43f, 0xFFFFE292), Triple(0.30f, 0.70f, 0xFFFFDC88),
        Triple(0.22f, 0.84f, 0xFFFFE292), Triple(0f, 0.88f, 0xFFFFE292)), 0.50f, 0.30f),
    MarkerLayer(104f, listOf(Triple(0f, 0.10f, 0xFFFFE69C), Triple(0.16f, 0.16f, 0xFFFFE69C), Triple(0.12f, 0.40f, 0xFFFFE69C),
        Triple(0f, 0.48f, 0xFFFFE69C)), 0.34f, 0.08f),
)

private fun DrawScope.drawMarker(rect: Rect, em: Float) {
    clipPath(markerShape(rect, em)) {
        markerLayers.forEach { layer ->
            val height = rect.height * layer.height
            val top = rect.top + (rect.height - height) * layer.position
            // CSS `linear-gradient(<angle>)`: the gradient line runs through the centre and is just
            // long enough for the corners to hit 0% and 100%.
            val radians = Math.toRadians(layer.angle.toDouble())
            val dx = sin(radians).toFloat()
            val dy = -cos(radians).toFloat()
            val half = (abs(rect.width * dx) + abs(height * dy)) / 2
            val mid = Offset(rect.center.x, top + height / 2)
            val brush = Brush.linearGradient(
                *layer.stops.map { (alpha, at, rgb) -> at to Color(rgb).copy(alpha = alpha) }.toTypedArray(),
                start = Offset(mid.x - dx * half, mid.y - dy * half), end = Offset(mid.x + dx * half, mid.y + dy * half),
            )
            drawRect(brush, Offset(rect.left, top), Size(rect.width, height))
        }
    }
}

/** `border-radius: 1.4em .35em 1.6em .5em / .7em 1.2em .45em 1em`, scaled down as CSS does on overflow. */
private fun markerShape(rect: Rect, em: Float): Path {
    var rx = floatArrayOf(1.4f, 0.35f, 1.6f, 0.5f).map { it * em } // TL, TR, BR, BL
    var ry = floatArrayOf(0.7f, 1.2f, 0.45f, 1.0f).map { it * em }
    val factor = minOf(1f, rect.width / (rx[0] + rx[1]), rect.width / (rx[3] + rx[2]),
        rect.height / (ry[0] + ry[3]), rect.height / (ry[1] + ry[2]))
    rx = rx.map { it * factor }
    ry = ry.map { it * factor }
    val k = 1 - 0.5523f
    return Path().apply {
        moveTo(rect.left + rx[0], rect.top)
        lineTo(rect.right - rx[1], rect.top)
        cubicTo(rect.right - rx[1] * k, rect.top, rect.right, rect.top + ry[1] * k, rect.right, rect.top + ry[1])
        lineTo(rect.right, rect.bottom - ry[2])
        cubicTo(rect.right, rect.bottom - ry[2] * k, rect.right - rx[2] * k, rect.bottom, rect.right - rx[2], rect.bottom)
        lineTo(rect.left + rx[3], rect.bottom)
        cubicTo(rect.left + rx[3] * k, rect.bottom, rect.left, rect.bottom - ry[3] * k, rect.left, rect.bottom - ry[3])
        lineTo(rect.left, rect.top + ry[0])
        cubicTo(rect.left, rect.top + ry[0] * k, rect.left + rx[0] * k, rect.top, rect.left + rx[0], rect.top)
        close()
    }
}

// MARK: - Data + timing model (`reveal-data.js`)

/** Seconds each row spends per slot; one full loop is `rows × step`. */
private const val REVEAL_STEP = 1.55f

private class RevealRowData(val name: String, val meta: String, val color: Long, val icon: String)

private val revealRows = listOf(
    RevealRowData("Risk Analizi Oluştur", "12 Aktif Analiz", 0xFF3B82F6,
        "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6l7-3zM12 8v4.5M12 15.5h.01"),
    RevealRowData("Açık Uygunsuzluklar", "34 Açık", 0xFFE4572E, "M12 4l8.5 15H3.5L12 4zM12 10v4M12 17h.01"),
    RevealRowData("Firma Yönetimi", "8 Firma", 0xFF4F46E5,
        "M4 21V5l8-2v18M12 8h8v13M4 21h16M8 8h.01M8 12h.01M8 16h.01M16 12h.01M16 16h.01"),
    RevealRowData("Gecikmiş Periyodik Kontrol", "7 Gün", 0xFFD97706, "M5 7h14v13H5zM5 12h14M10 4v3M14 4v3"),
    RevealRowData("Kapatılan DÖF’ler", "↗ %18 · 46 Adet", 0xFF16A34A, "M7 3h7l4 4v14H7zM14 3v4h4M10 14l2 2 3.5-3.5"),
    RevealRowData("Acil Durum Eylem Planı", "3 Güncelleme", 0xFFF97316, "M13 3l-1.5 7H16l-5 11 1.2-7.5H8L13 3z"),
    RevealRowData("Eğitimi Geçen Personel", "128 Kişi", 0xFF0EA5A5,
        "M9 11a3.2 3.2 0 100-6.4 3.2 3.2 0 000 6.4zM3.5 19.5c0-3 2.5-5 5.5-5s5.5 2 5.5 5M17 8.6a2.6 2.6 0 010 5.2M16.6 15c2.3.3 4 2.1 4 4.5"),
    RevealRowData("AdamxSaat Eğitim Süresi", "1.240 Saat", 0xFF6366F1, "M12 3a9 9 0 100 18 9 9 0 000-18zM12 7.5V12l3.2 2"),
    RevealRowData("Fotoğraf Analiz", "56 Tespit", 0xFF0891B2, "M4 8h3l2-3h6l2 3h3v11H4zM12 17a3.5 3.5 0 100-7 3.5 3.5 0 000 7z"),
    RevealRowData("Tatbikat Yönetimi", "2 Planlı", 0xFF7C3AED, "M5 21V4M5 4h11l-2 4 2 4H5"),
    RevealRowData("Yüksek Uygunsuzluk Oranı", "↗ %12,4", 0xFFDB2777, "M4 19h16M6 15l4-4 3 3 5-6M14 8h4v4"),
    RevealRowData("Kritik Uygunsuzluk Oranı", "%3,1", 0xFFDC2626, "M8.5 3h7L21 8.5v7L15.5 21h-7L3 15.5v-7zM12 8v5M12 16h.01"),
    RevealRowData("Firma Skoru", "86 / 100", 0xFFCA8A04, "M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.8l-5.2 2.8 1-5.8-4.3-4.1 5.9-.9z"),
    RevealRowData("Firma Bazlı İstatistikler", "8 Firma · 24 Rapor", 0xFF2563EB, "M4 20V10M10 20V4M16 20v-7M22 20H2"),
    RevealRowData("OSGB Bazlı İstatistikler", "3 OSGB · %91", 0xFF0D9488, "M12 3a9 9 0 109 9h-9V3zM15 3.5A8 8 0 0120.5 9H15V3.5z"),
    RevealRowData("Uzman Atamaları", "14 Uzman · 2 Bekleyen", 0xFF9333EA,
        "M9 11a3.2 3.2 0 100-6.4 3.2 3.2 0 000 6.4zM3.5 19.5c0-3 2.5-5 5.5-5s5.5 2 5.5 5M16 11l2 2 4-4"),
)

/** Slot table keyed by position relative to the active row (+ below, − above): translateY, opacity, blur. */
private val revealSlots = mapOf(
    6 to Triple(288f, 0f, 1.2f), 5 to Triple(240f, 0f, 1.2f), 4 to Triple(192f, 0.12f, 3f), 3 to Triple(144f, 0.28f, 2.2f),
    2 to Triple(96f, 0.44f, 1.6f), 1 to Triple(48f, 0.62f, 0.9f),
    -1 to Triple(-53f, 0.36f, 1.2f), -2 to Triple(-106f, 0.14f, 2f), -3 to Triple(-159f, 0f, 1.05f), -4 to Triple(-212f, 0f, 1.2f),
    -5 to Triple(-265f, 0f, 1.2f),
)

/** Share of each slot spent holding still; the rest is the slide. */
private const val REVEAL_HOLD = 0.672f
private val revealSlide = CubicBezierEasing(0.36f, 0.02f, 0.2f, 1f)
private val revealPop = CubicBezierEasing(0.2f, 0.7f, 0.3f, 1f)
private val revealSettle = CubicBezierEasing(0.45f, 0f, 0.35f, 1f)

/** A colour that interpolates the way CSS does (premultiplied sRGB), so a transparent end never tints the blend. */
private data class RevealRgba(val r: Float, val g: Float, val b: Float, val a: Float) {
    fun mix(other: RevealRgba, t: Float): RevealRgba {
        val alpha = a + (other.a - a) * t
        if (alpha <= 0f) return RevealRgba(0f, 0f, 0f, 0f)
        fun channel(from: Float, to: Float) = (from * a * (1 - t) + to * other.a * t) / alpha
        return RevealRgba(channel(r, other.r), channel(g, other.g), channel(b, other.b), alpha)
    }

    val color: Color get() = Color(r, g, b, a)

    companion object {
        fun of(argb: Long, alpha: Float = 1f): RevealRgba {
            val c = Color(argb)
            return RevealRgba(c.red, c.green, c.blue, alpha)
        }
    }
}

private data class RevealRowStyle(
    val offsetY: Float, val scale: Float, val opacity: Float, val blur: Float,
    val background: RevealRgba, val ring: Float, val ringColor: RevealRgba,
    val shadowY: Float, val shadowBlur: Float, val shadowAlpha: Float,
    val border: RevealRgba, val icon: RevealRgba, val verticalPadding: Float, val zIndex: Float,
) {
    fun mix(other: RevealRowStyle, t: Float): RevealRowStyle {
        fun lerp(a: Float, b: Float) = a + (b - a) * t
        return RevealRowStyle(
            lerp(offsetY, other.offsetY), lerp(scale, other.scale), lerp(opacity, other.opacity), lerp(blur, other.blur),
            background.mix(other.background, t), lerp(ring, other.ring), ringColor.mix(other.ringColor, t),
            lerp(shadowY, other.shadowY), lerp(shadowBlur, other.shadowBlur), lerp(shadowAlpha, other.shadowAlpha),
            border.mix(other.border, t), icon.mix(other.icon, t), lerp(verticalPadding, other.verticalPadding),
            lerp(zIndex, other.zIndex).roundToInt().toFloat(),
        )
    }
}

/** Fraction of the loop a row is at, 0 until 1. */
private fun revealPhase(elapsed: Float, index: Int, cycle: Float): Float {
    val raw = (elapsed + index * REVEAL_STEP) / cycle
    return raw - floor(raw)
}

private fun revealPlain(slot: Int): RevealRowStyle {
    val value = revealSlots[slot] ?: if (slot > 0) Triple(288f, 0f, 1.2f) else Triple(-265f - (abs(slot) - 5) * 53f, 0f, 1.2f)
    return RevealRowStyle(value.first, if (slot > 0) 0.97f else 0.92f, value.second, value.third,
        RevealRgba.of(0xFFFFFFFF, 0f), 0f, RevealRgba.of(0xFF18263A, 0f), 0f, 0f, 0f,
        RevealRgba.of(0xFFEAEEF4, 0f), RevealRgba.of(0xFF8E99A4), 12f, 1f)
}

private fun revealActive(tint: Long, scale: Float, ring: Float, ringAlpha: Float, shadowY: Float, shadowBlur: Float,
                         shadowAlpha: Float, border: RevealRgba) =
    RevealRowStyle(0f, scale, 1f, 0f, RevealRgba.of(0xFFFFFFFF), ring, RevealRgba.of(tint, ringAlpha),
        shadowY, shadowBlur, shadowAlpha, border, RevealRgba.of(tint), 14f, 4f)

/** Arrival (1.04) → pop (1.075) → settled (1.05), the active slot's three keyframes. */
private fun revealActiveStates(tint: Long): Triple<RevealRowStyle, RevealRowStyle, RevealRowStyle> {
    val color = RevealRgba.of(tint)
    return Triple(
        revealActive(tint, 1.04f, 0f, 0f, 12f, 30f, 0.16f, color.mix(RevealRgba.of(0xFFEAEEF4), 0.82f)),
        revealActive(tint, 1.075f, 5f, 0.14f, 22f, 44f, 0.2f, color.mix(RevealRgba.of(0xFFFFFFFF), 0.55f)),
        revealActive(tint, 1.05f, 3f, 0.09f, 16f, 36f, 0.17f, color.mix(RevealRgba.of(0xFFFFFFFF), 0.68f)),
    )
}

private fun revealStyle(phase: Float, tint: Long): RevealRowStyle {
    val count = revealRows.size
    val position = phase * count
    val step = min(count - 1, position.toInt())
    val local = position - step
    val slot = 6 - step
    if (slot == 0) {
        val (arrive, peak, settled) = revealActiveStates(tint)
        return when {
            local < 0.228f -> arrive.mix(peak, revealPop.transform(local / 0.228f))
            local < REVEAL_HOLD -> peak.mix(settled, revealSettle.transform((local - 0.228f) / (REVEAL_HOLD - 0.228f)))
            else -> settled.mix(revealPlain(-1), revealSlide.transform((local - REVEAL_HOLD) / (1 - REVEAL_HOLD)))
        }
    }
    // The last slot holds until the loop wraps, invisibly, to the bottom.
    if (step == count - 1 || local < REVEAL_HOLD) return revealPlain(slot)
    val next = if (slot - 1 == 0) revealActiveStates(tint).first else revealPlain(slot - 1)
    return revealPlain(slot).mix(next, revealSlide.transform((local - REVEAL_HOLD) / (1 - REVEAL_HOLD)))
}

/** `isgHaloN`: the glow starts slightly before its card slides in, so it never reads as trailing it. */
private fun revealHaloOpacity(phase: Float): Float {
    val unit = 100f / revealRows.size
    val start = 6 * unit
    val stops = listOf(0f to 0f, start - 0.78f * unit to 0f, start - 0.42f * unit to 0.08f, start + 0.06f * unit to 0.09f,
        start + 0.42f * unit to 0.07f, start + 0.65f * unit to 0f, 100f to 0f)
    val percent = phase * 100
    for (index in 1 until stops.size) {
        val (x1, y1) = stops[index]
        if (percent <= x1) {
            val (x0, y0) = stops[index - 1]
            return if (x1 > x0) y0 + (y1 - y0) * (percent - x0) / (x1 - x0) else y1
        }
    }
    return 0f
}
