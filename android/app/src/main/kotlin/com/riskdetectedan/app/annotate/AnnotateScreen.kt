package com.riskdetectedan.app.annotate

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource
import androidx.annotation.StringRes

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Path as AndroidPath
import android.graphics.PorterDuff
import android.graphics.RectF
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CropSquare
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Real port of `AnnotationTool` (`App/Models/Annotation.swift`) — icons are the closest Material
 * equivalents to the SF Symbols (`square`/`circle`/`arrow.up.right`/`scribble`), not a redesign. */
enum class AnnotationTool(val icon: ImageVector, @StringRes val labelRes: Int) {
    Rect(Icons.Filled.CropSquare, RdR.string.rd_annotate_box),
    Circle(Icons.Filled.Circle, RdR.string.rd_annotate_circle),
    Arrow(Icons.Filled.NorthEast, RdR.string.rd_annotate_arrow),
    Pen(Icons.Filled.Draw, RdR.string.rd_annotate_pen),
}

/** Real port of `AnnotationColor` — same 3 hex values as iOS (`rdGreen`/`#B42318`/`#FFD75A`). */
enum class AnnotationColor(val color: Color) {
    Green(Color(0xFF00B82E)),
    Red(Color(0xFFB42318)),
    Yellow(Color(0xFFFFD75A)),
}

private data class ShapeAnnotation(val tool: AnnotationTool, val color: AnnotationColor, val start: Offset, val end: Offset)
private data class PenStroke(val color: AnnotationColor, val points: List<Offset>)

/**
 * Real port of `AnnotateView.swift` — draw-on-photo hazard markup: box/circle/arrow shapes (drag
 * gesture) + freehand pen (PencilKit on iOS, a plain Compose drag-collected [PenStroke] path
 * here — same real capability, no third-party ink SDK needed for straight/curved strokes), 3
 * accent colors, undo (shapes before pen strokes, matching the Swift `undoLast()` precedence
 * exactly). All coordinates are stored normalized (0..1) against the photo *container* box, not
 * the fitted image rect — same convention `shapeDragGesture`/`AnnotationShape` use on iOS, which
 * is what makes the flatten step's letterbox math line up with what was actually drawn on screen.
 *
 * [onAnalyze] receives a path to a newly-written flattened JPEG (original photo + all markup
 * composited, target long edge clamped to the same 1600-2400px budget as iOS's
 * `flattenedRenderPlan()`) — never mutates [photoPath] in place, matches iOS's
 * `updateAnnotatedPhoto` semantics of producing a *new* image the caller then swaps in.
 */
@Composable
fun AnnotateScreen(
    photoPath: String,
    primaryActionTitle: String? = null,
    onCancel: () -> Unit,
    onAnalyze: (String) -> Unit,
) {
    val context = LocalContext.current
    val resolvedPrimaryActionTitle = primaryActionTitle ?: stringResource(RdR.string.rd_isaretli_alanlari_analiz_et)
    val original = remember(photoPath) { BitmapFactory.decodeFile(photoPath) }

    var tool by remember { mutableStateOf(AnnotationTool.Rect) }
    var color by remember { mutableStateOf(AnnotationColor.Green) }
    var shapes by remember { mutableStateOf(listOf<ShapeAnnotation>()) }
    var penStrokes by remember { mutableStateOf(listOf<PenStroke>()) }
    var dragStart by remember { mutableStateOf<Offset?>(null) }
    var dragEnd by remember { mutableStateOf<Offset?>(null) }
    var currentPenPoints by remember { mutableStateOf(listOf<Offset>()) }
    var boxSize by remember { mutableStateOf(IntSize.Zero) }

    fun undoLast() {
        if (shapes.isNotEmpty()) {
            shapes = shapes.dropLast(1)
        } else if (penStrokes.isNotEmpty()) {
            penStrokes = penStrokes.dropLast(1)
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Color(0xFF0B0D0E))) {
        // Top bar
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButtonChip(icon = Icons.Filled.Close, contentDescription = stringResource(RdR.string.rd_kapat), onClick = onCancel)
            Spacer(Modifier.weight(1f))
            Text(stringResource(RdR.string.rd_i_saretleme), style = RdFontStyle.Callout.toTextStyle(), color = Color.White)
            Spacer(Modifier.weight(1f))
            IconButtonChip(icon = Icons.Filled.Undo, contentDescription = stringResource(RdR.string.rd_geri_al), onClick = ::undoLast)
        }

        // Photo + annotation layer
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .padding(vertical = 8.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Color.Black)
                .onSizeChanged { boxSize = it }
                .pointerInput(tool, color, boxSize) {
                    if (boxSize.width <= 0 || boxSize.height <= 0) return@pointerInput
                    val size = Size(boxSize.width.toFloat(), boxSize.height.toFloat())
                    detectDragGestures(
                        onDragStart = { offset ->
                            if (tool == AnnotationTool.Pen) {
                                currentPenPoints = listOf(offset)
                            } else {
                                dragStart = offset
                                dragEnd = offset
                            }
                        },
                        onDrag = { change, _ ->
                            change.consume()
                            if (tool == AnnotationTool.Pen) {
                                currentPenPoints = currentPenPoints + change.position
                            } else {
                                dragEnd = change.position
                            }
                        },
                        onDragEnd = {
                            if (tool == AnnotationTool.Pen) {
                                if (currentPenPoints.size > 1) {
                                    penStrokes = penStrokes + PenStroke(color, currentPenPoints.map { it / size })
                                }
                                currentPenPoints = emptyList()
                            } else {
                                val s = dragStart
                                val e = dragEnd
                                if (s != null && e != null) {
                                    val sn = s / size
                                    val en = e / size
                                    if (kotlin.math.abs(en.x - sn.x) > 0.02f || kotlin.math.abs(en.y - sn.y) > 0.02f) {
                                        shapes = shapes + ShapeAnnotation(tool, color, sn, en)
                                    }
                                }
                                dragStart = null
                                dragEnd = null
                            }
                        },
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            val bitmap = remember(original) { original?.asImageBitmap() }
            if (bitmap != null) {
                Image(
                    bitmap = bitmap,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            }

            Canvas(modifier = Modifier.fillMaxSize()) {
                shapes.forEach { drawShape(it, this.size) }
                if (tool != AnnotationTool.Pen && dragStart != null && dragEnd != null) {
                    val sizePx = this.size
                    val sn = dragStart!! / Size(sizePx.width, sizePx.height)
                    val en = dragEnd!! / Size(sizePx.width, sizePx.height)
                    drawShape(ShapeAnnotation(tool, color, sn, en), sizePx, alpha = 0.85f)
                }
                penStrokes.forEach { drawPenStroke(it, this.size) }
                if (tool == AnnotationTool.Pen && currentPenPoints.size > 1) {
                    val sizePx = this.size
                    drawPenStroke(PenStroke(color, currentPenPoints.map { it / Size(sizePx.width, sizePx.height) }), sizePx)
                }
            }
        }

        // Tool + color toolbar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Color.White.copy(alpha = 0.95f))
                .padding(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AnnotationTool.entries.forEach { t ->
                val active = tool == t
                val toolLabel = stringResource(t.labelRes)
                Column(
                    modifier = Modifier
                        .size(width = 52.dp, height = 44.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (active) Color(0xFF0B0D0E) else Color.Transparent)
                        .clickable { tool = t },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(t.icon, contentDescription = toolLabel, tint = if (active) Color.White else Color.Black, modifier = Modifier.size(16.dp))
                    Text(toolLabel, style = RdFontStyle.Caption.toTextStyle(), color = if (active) Color.White else Color.Black)
                }
            }
            Box(modifier = Modifier.width(1.dp).height(28.dp).padding(horizontal = 4.dp).background(Color.Black.copy(alpha = 0.12f)))
            Row(modifier = Modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AnnotationColor.entries.forEach { c ->
                    val active = color == c
                    Box(
                        modifier = Modifier
                            .size(22.dp)
                            .clip(CircleShape)
                            .background(c.color)
                            .border(2.dp, Color.White, CircleShape)
                            .border(2.dp, if (active) Color(0xFF0B0D0E) else Color.Transparent, CircleShape)
                            .clickable { color = c },
                    )
                }
            }
        }

        RdPrimaryButton(
            text = resolvedPrimaryActionTitle,
            onClick = {
                val output = flattenAnnotatedImage(context, original, boxSize, shapes, penStrokes)
                if (output != null) onAnalyze(output) else onCancel()
            },
            style = RdButtonStyle.Green,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 16.dp),
        )
    }
}

@Composable
private fun IconButtonChip(icon: ImageVector, contentDescription: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Color.White.copy(alpha = 0.12f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = contentDescription, tint = Color.White, modifier = Modifier.size(16.dp))
    }
}

private operator fun Offset.div(size: Size): Offset = Offset(x / size.width, y / size.height)
private operator fun Offset.times(size: Size): Offset = Offset(x * size.width, y * size.height)

private fun DrawScope.drawShape(
    shape: ShapeAnnotation,
    canvasSize: Size,
    alpha: Float = 1f,
) {
    val s = shape.start * canvasSize
    val e = shape.end * canvasSize
    val topLeft = Offset(min(s.x, e.x), min(s.y, e.y))
    val rectSize = Size(kotlin.math.abs(e.x - s.x), kotlin.math.abs(e.y - s.y))
    when (shape.tool) {
        AnnotationTool.Rect -> {
            drawRoundRect(shape.color.color.copy(alpha = 0.12f * alpha), topLeft = topLeft, size = rectSize, cornerRadius = CornerRadius(6.dp.toPx()))
            drawRoundRect(shape.color.color.copy(alpha = alpha), topLeft = topLeft, size = rectSize, cornerRadius = CornerRadius(6.dp.toPx()), style = Stroke(width = 3.dp.toPx()))
        }
        AnnotationTool.Circle -> {
            drawOval(shape.color.color.copy(alpha = 0.10f * alpha), topLeft = topLeft, size = rectSize)
            drawOval(shape.color.color.copy(alpha = alpha), topLeft = topLeft, size = rectSize, style = Stroke(width = 3.dp.toPx()))
        }
        AnnotationTool.Arrow -> {
            drawLine(shape.color.color.copy(alpha = alpha), start = s, end = e, strokeWidth = 3.dp.toPx(), cap = StrokeCap.Round)
            val angle = atan2(e.y - s.y, e.x - s.x)
            val arrowSize = 12.dp.toPx()
            val a1 = angle + Math.PI.toFloat() - Math.PI.toFloat() / 7f
            val a2 = angle + Math.PI.toFloat() + Math.PI.toFloat() / 7f
            val path = Path().apply {
                moveTo(e.x, e.y)
                lineTo(e.x + cos(a1) * arrowSize, e.y + sin(a1) * arrowSize)
                lineTo(e.x + cos(a2) * arrowSize, e.y + sin(a2) * arrowSize)
                close()
            }
            drawPath(path, shape.color.color.copy(alpha = alpha))
        }
        AnnotationTool.Pen -> Unit
    }
}

private fun DrawScope.drawPenStroke(stroke: PenStroke, canvasSize: Size) {
    if (stroke.points.size < 2) return
    val path = Path()
    val first = stroke.points.first() * canvasSize
    path.moveTo(first.x, first.y)
    stroke.points.drop(1).forEach { p ->
        val pt = p * canvasSize
        path.lineTo(pt.x, pt.y)
    }
    drawPath(path, stroke.color.color, style = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/** Real port of `flattenedImage()` — black letterbox background, base photo aspect-fit into the
 * *container*'s aspect (same container the normalized coordinates were captured against, matching
 * iOS's `aspectFitRect(imageSize:in:)`), pen strokes then shapes composited on top, target long
 * edge clamped to 1600-2400px (`minFlattenedLongEdge`/`maxFlattenedLongEdge`). Writes to a new
 * cache file rather than mutating [photoPath] in place. */
private fun flattenAnnotatedImage(
    context: android.content.Context,
    original: Bitmap?,
    boxSize: IntSize,
    shapes: List<ShapeAnnotation>,
    penStrokes: List<PenStroke>,
): String? {
    if (original == null || boxSize.width <= 0 || boxSize.height <= 0) return null

    val displayLongEdge = max(boxSize.width, boxSize.height).toFloat()
    val sourceLongEdge = max(original.width, original.height).toFloat()
    val targetLongEdge = sourceLongEdge.coerceIn(1600f, 2400f)
    val scale = max(1f, targetLongEdge / displayLongEdge)
    val targetW = max(1, (boxSize.width * scale).roundToInt())
    val targetH = max(1, (boxSize.height * scale).roundToInt())

    val output = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
    val canvas = android.graphics.Canvas(output)
    canvas.drawColor(android.graphics.Color.BLACK, PorterDuff.Mode.SRC)

    // Base photo, aspect-fit into the target rect (same fit as ContentScale.Fit on screen).
    val imageAr = original.width.toFloat() / original.height.toFloat()
    val containerAr = targetW.toFloat() / targetH.toFloat()
    val fitRect = if (imageAr > containerAr) {
        val h = targetW / imageAr
        RectF(0f, (targetH - h) / 2f, targetW.toFloat(), (targetH - h) / 2f + h)
    } else {
        val w = targetH * imageAr
        RectF((targetW - w) / 2f, 0f, (targetW - w) / 2f + w, targetH.toFloat())
    }
    canvas.drawBitmap(original, null, fitRect, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))

    // Pen strokes (container-normalized -> target pixels).
    val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        strokeWidth = max(3f * scale, 3f)
    }
    penStrokes.forEach { stroke ->
        if (stroke.points.size < 2) return@forEach
        val path = AndroidPath()
        val first = stroke.points.first()
        path.moveTo(first.x * targetW, first.y * targetH)
        stroke.points.drop(1).forEach { p -> path.lineTo(p.x * targetW, p.y * targetH) }
        strokePaint.color = stroke.color.color.toArgb()
        canvas.drawPath(path, strokePaint)
    }

    // Shapes.
    shapes.forEach { shape ->
        val sx = shape.start.x * targetW
        val sy = shape.start.y * targetH
        val ex = shape.end.x * targetW
        val ey = shape.end.y * targetH
        val rect = RectF(min(sx, ex), min(sy, ey), max(sx, ex), max(sy, ey))
        val lineWidth = max(3f * scale, 3f)
        val argb = shape.color.color.toArgb()
        when (shape.tool) {
            AnnotationTool.Rect -> {
                val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = argb; alpha = (0.12f * 255).roundToInt() }
                val strokePaintShape = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = argb; strokeWidth = lineWidth }
                canvas.drawRoundRect(rect, 6f * scale, 6f * scale, fillPaint)
                canvas.drawRoundRect(rect, 6f * scale, 6f * scale, strokePaintShape)
            }
            AnnotationTool.Circle -> {
                val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = argb; alpha = (0.10f * 255).roundToInt() }
                val strokePaintShape = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = argb; strokeWidth = lineWidth }
                canvas.drawOval(rect, fillPaint)
                canvas.drawOval(rect, strokePaintShape)
            }
            AnnotationTool.Arrow -> {
                val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = argb; strokeWidth = lineWidth; strokeCap = Paint.Cap.ROUND }
                canvas.drawLine(sx, sy, ex, ey, linePaint)
                val angle = atan2(ey - sy, ex - sx)
                val arrowSize = 12f * scale
                val a1 = angle + Math.PI.toFloat() - Math.PI.toFloat() / 7f
                val a2 = angle + Math.PI.toFloat() + Math.PI.toFloat() / 7f
                val headPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = argb }
                val head = AndroidPath().apply {
                    moveTo(ex, ey)
                    lineTo(ex + cos(a1) * arrowSize, ey + sin(a1) * arrowSize)
                    lineTo(ex + cos(a2) * arrowSize, ey + sin(a2) * arrowSize)
                    close()
                }
                canvas.drawPath(head, headPaint)
            }
            AnnotationTool.Pen -> Unit
        }
    }

    val file = File(context.cacheDir, "annotated_${UUID.randomUUID()}.jpg")
    FileOutputStream(file).use { stream ->
        output.compress(Bitmap.CompressFormat.JPEG, 90, stream)
    }
    return file.absolutePath
}
