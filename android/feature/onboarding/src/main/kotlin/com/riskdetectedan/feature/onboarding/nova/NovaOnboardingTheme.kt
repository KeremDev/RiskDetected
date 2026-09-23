package com.riskdetectedan.feature.onboarding.nova

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.riskdetectedan.core.designsystem.isg.NovaFontFamilyPublic
import com.riskdetectedan.core.designsystem.isg.novaPress
import com.riskdetectedan.core.designsystem.isg.rememberNovaReduceMotion
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Design tokens transcribed from the Claude Design prototype (`İSGADA Onboarding.dc.html` /
 * `İSGADA Giriş.dc.html`), same values as iOS `NovaOB`, so both platforms draw the funnel alike.
 */
internal object NovaOB {
    val ink = Color(0xFF000000)
    val inkSoft = Color(0xFF2C3336)
    val slate = Color(0xFF3A4548)
    val muted = Color(0xFF5A5A5A)
    val muted2 = Color(0xFF767676)
    val disabled = Color(0xFF9A9A9A)
    val line = Color(0xFFE4E4E4)
    val line2 = Color(0xFFC9C9C9)
    val surface = Color(0xFFFFFFFF)
    val fill = Color(0xFFF1F1F1)
    val fill2 = Color(0xFFF4F4F4)
    val fill3 = Color(0xFFF7F7F7)
    val errorInk = Color(0xFFA4453C)
    val errorBg = Color(0xFFFBECEA)
    val errorBorder = Color(0xFFC97A72)
    val gold = Color(0xFFC8873F)

    val intro1Bg = Color(0xFFF6DCD6)
    val intro2Bg = Color(0xFFEAF5CE)
    val intro3Bg = Color(0xFFFBE1CD)
    val socialBg = Color(0xFFDCE9F6)

    /** Experience slider tints, one per stop. */
    val stopTint = listOf(Color(0xFF000000), Color(0xFF8A6B4F), Color(0xFFC06A3A), Color(0xFFC0392B))

    const val CHECK = "M2 7.5l3.4 3.4L12 3.5"
    const val MAIL = "M2.5 4.5h19v15h-19z|M3 7.5l9 6 9-6"
    const val LOCK = "M4 10.5h16v10.5H4z|M8 10.5V7.5a4 4 0 018 0v3"
    const val RESEND = "M20 11a8 8 0 10-2.6 5.9|M20 4.5V11h-6"
    const val DONE_CIRCLE = "circle:12,12,9.2|M7.8 12.3l2.9 2.9 5.5-6"
}

/**
 * Plus Jakarta Sans at a fixed size. The prototype's layout is too tight for font scaling (iOS
 * keeps Dynamic Type off here for the same reason), so the size ignores the system font scale.
 */
@Composable
internal fun obStyle(size: Float, weight: Int = 400, color: Color = NovaOB.ink, lineHeight: Float? = null,
                     tracking: Float = 0f, italic: Boolean = false): TextStyle {
    val scale = LocalDensity.current.fontScale
    fun unit(value: Float): TextUnit = (value / scale).sp
    return TextStyle(
        fontFamily = NovaFontFamilyPublic,
        fontWeight = when {
            weight >= 800 -> FontWeight.ExtraBold
            weight >= 700 -> FontWeight.Bold
            weight >= 600 -> FontWeight.SemiBold
            weight >= 500 -> FontWeight.Medium
            weight <= 300 -> FontWeight.Light
            else -> FontWeight.Normal
        },
        fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal,
        fontSize = unit(size),
        lineHeight = lineHeight?.let { unit(size * it) } ?: TextUnit.Unspecified,
        letterSpacing = unit(tracking),
        color = color,
    )
}

@Composable
internal fun ObText(text: String, size: Float, modifier: Modifier = Modifier, weight: Int = 400, color: Color = NovaOB.ink,
                    lineHeight: Float? = null, tracking: Float = 0f, align: TextAlign? = null, maxLines: Int = Int.MAX_VALUE,
                    italic: Boolean = false, strike: Boolean = false) {
    Text(text, modifier, style = obStyle(size, weight, color, lineHeight, tracking, italic)
        .copy(textDecoration = if (strike) TextDecoration.LineThrough else null),
        textAlign = align, maxLines = maxLines)
}

/**
 * The prototype measures padding from the very top and bottom of the frame, status bar and
 * navigation bar included. The app root already lays content out inside the safe area, so the
 * design value is reduced by the inset to land in the same place on screen.
 */
@Composable
internal fun obPadTop(design: Float): Dp {
    val density = LocalDensity.current
    val inset = with(density) { WindowInsets.statusBars.getTop(density).toDp() }
    return max(0f, design - inset.value).dp
}

@Composable
internal fun obPadBottom(design: Float): Dp {
    val density = LocalDensity.current
    val inset = with(density) { WindowInsets.navigationBars.getBottom(density).toDp() }
    return max(0f, design - inset.value).dp
}

/**
 * A scroll column at least as tall as the visible area, so a weighted spacer can push a footer to
 * the bottom without ever pushing it off screen.
 */
@Composable
internal fun ObFittedScroll(padding: PaddingValues, spacing: Dp, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val minHeight = maxHeight
        // An unbounded column distributes weights over its minimum height, so a weighted spacer
        // fills the screen when content is short and collapses when content scrolls.
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = minHeight).padding(padding),
            verticalArrangement = Arrangement.spacedBy(spacing), content = content)
    }
}

// MARK: - Shared primitives

/** The black pill CTA used on every marketing screen (intro, card, push, trial). */
@Composable
internal fun ObPillButton(title: String, modifier: Modifier = Modifier, height: Float = 60f, fontSize: Float = 17.5f,
                          horizontalPadding: Float? = null, fixedWidth: Float? = null, showsArrow: Boolean = false,
                          background: Color = NovaOB.ink, onClick: () -> Unit) {
    val sized = when {
        fixedWidth != null -> Modifier.width(fixedWidth.dp)
        horizontalPadding != null -> Modifier
        else -> Modifier.fillMaxWidth()
    }
    Row(modifier.then(sized).height(height.dp).clip(CircleShape).background(background).novaPress(onClick = onClick)
        .padding(horizontal = (horizontalPadding ?: 0f).dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        ObText(title, fontSize, weight = 700, color = Color.White, maxLines = 1)
        if (showsArrow) ObArrowRight(18f, Color.White)
    }
}

/** The squared 56 pt / radius 16 primary button used on form screens. */
@Composable
internal fun ObPrimaryButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, showsArrow: Boolean = false,
                             busy: Boolean = false, onClick: () -> Unit) {
    val ink = if (enabled) Color.White else NovaOB.disabled
    Row(modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(16.dp))
        .background(if (enabled) NovaOB.ink else Color(0xFFDDDDDD)).novaPress(enabled = enabled && !busy, onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        ObText(title, 17f, weight = 600, color = ink)
        if (showsArrow) ObArrowRight(18f, ink)
    }
}

/** White button with a 2 pt black border — the Giriş screen's mail CTA. */
@Composable
internal fun ObOutlineButton(title: String, busy: Boolean = false, icon: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Row(Modifier.fillMaxWidth().height(56.dp).clip(shape).background(NovaOB.surface).border(2.dp, NovaOB.ink, shape)
        .novaPress(onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        icon?.invoke()
        ObText(title, 17f, weight = 700)
        if (busy) ObSpinner(17f, NovaOB.line, NovaOB.ink)
    }
}

/** The 26×3 progress pills at the top of the intro screens. */
@Composable
internal fun ObDots(active: Int, count: Int = 4) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(count) { index ->
            Box(Modifier.size(26.dp, 3.dp).clip(CircleShape).background(if (index == active) NovaOB.ink else NovaOB.ink.copy(alpha = 0.2f)))
        }
    }
}

@Composable
internal fun ObBackButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(modifier.size(44.dp).novaPress(onClick = onClick), contentAlignment = Alignment.Center) {
        ObIcon("M9 1L2 9l7 8", width = 11f, height = 18f, color = NovaOB.ink, lineWidth = 2f, viewBoxWidth = 11f, viewBoxHeight = 18f)
    }
}

@Composable
internal fun ObChevronRight(color: Color = NovaOB.line2) {
    ObIcon("M1 1l6 6-6 6", width = 8f, height = 14f, color = color, lineWidth = 2f, viewBoxWidth = 8f, viewBoxHeight = 14f)
}

@Composable
internal fun ObArrowRight(size: Float = 18f, color: Color = Color.White) {
    ObIcon("M4 12h15|M13 6l6 6-6 6", size, color, lineWidth = 2f)
}

@Composable
internal fun ObSpinner(size: Float = 16f, track: Color = NovaOB.line, head: Color = NovaOB.ink) {
    val reduceMotion = rememberNovaReduceMotion()
    val turn by rememberInfiniteTransition(label = "ob-spinner").animateFloat(0f, 360f,
        infiniteRepeatable(tween(720, easing = LinearEasing), RepeatMode.Restart), label = "ob-spinner-turn")
    Canvas(Modifier.size(size.dp).rotate(if (reduceMotion) 0f else turn)) {
        val width = 2.dp.toPx()
        drawArc(Brush.sweepGradient(listOf(track, head)), 0f, 0.72f * 360f, false,
            topLeft = Offset(width / 2, width / 2),
            size = androidx.compose.ui.geometry.Size(this.size.width - width, this.size.height - width),
            style = Stroke(width, cap = StrokeCap.Round))
    }
}

/** The prototype's inline error card (red ink on a tinted surface). */
@Composable
internal fun ObErrorNote(text: String) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(NovaOB.errorBg).padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp)) {
        ObIcon("circle:12,12,9.2|M12 7.6v6|M12 16.4h.01", 17f, NovaOB.errorInk, lineWidth = 1.9f, modifier = Modifier.padding(top = 1.dp))
        ObText(text, 14f, Modifier.weight(1f), color = NovaOB.errorInk, lineHeight = 1.4f)
    }
}

/** Neutral confirmation card (OTP success / reset-sent states). */
@Composable
internal fun ObInfoNote(text: String, icon: String? = null, background: Color = NovaOB.fill2) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(background).padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (icon != null) ObIcon(icon, 18f, NovaOB.ink, lineWidth = 2f, modifier = Modifier.padding(top = 1.dp))
        ObText(text, 14.5f, Modifier.weight(1f), lineHeight = 1.45f)
    }
}

/**
 * Text-field chrome shared by every input in both prototypes: optional leading icon, the text,
 * an optional trailing control, and a border that turns ink while focused.
 */
@Composable
internal fun ObField(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier,
                     height: Float = 54f, radius: Float = 14f, fontSize: Float = 16.5f, leadingIcon: String? = null,
                     errorBorder: Boolean = false, focusBorder: Color = NovaOB.ink, idleBorder: Color = NovaOB.line,
                     keyboardType: KeyboardType = KeyboardType.Text, secure: Boolean = false, singleLine: Boolean = true,
                     align: TextAlign = TextAlign.Start, onDone: (() -> Unit)? = null,
                     trailing: (@Composable RowScope.() -> Unit)? = null) {
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(radius.dp)
    val border = when {
        focused -> focusBorder
        errorBorder -> NovaOB.errorBorder
        else -> idleBorder
    }
    val style = obStyle(fontSize).copy(textAlign = align)
    BasicTextField(value, onValueChange, modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
        textStyle = style, singleLine = singleLine, cursorBrush = SolidColor(NovaOB.ink),
        visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onDone = { onDone?.invoke() }),
        decorationBox = { inner ->
            Row(Modifier.fillMaxWidth().height(height.dp).clip(shape).background(NovaOB.surface).border(1.5.dp, border, shape),
                verticalAlignment = Alignment.CenterVertically) {
                if (leadingIcon != null) {
                    ObIcon(leadingIcon, 19f, NovaOB.muted2, lineWidth = 1.7f, modifier = Modifier.padding(start = 16.dp))
                }
                Box(Modifier.weight(1f).padding(start = if (leadingIcon != null) 8.dp else 16.dp, end = if (trailing != null) 0.dp else 16.dp)) {
                    if (value.isEmpty()) Text(placeholder, style = style.copy(color = NovaOB.muted2), modifier = Modifier.fillMaxWidth())
                    inner()
                }
                trailing?.invoke(this)
            }
        })
}

// MARK: - SVG-ish path renderer

/**
 * Draws the prototype's inline SVG icons. Segments are separated by `|`; `circle:cx,cy,r` draws a
 * circle, everything else is an SVG path in a 24×24 view box (iOS `NovaOBIconPath`).
 */
@Composable
internal fun ObIcon(path: String, size: Float = 24f, color: Color = NovaOB.ink, lineWidth: Float = 1.5f,
                    modifier: Modifier = Modifier, viewBox: Float = 24f, filled: Boolean = false) {
    ObIcon(path, size, size, color, lineWidth, modifier, viewBox, viewBox, filled)
}

@Composable
internal fun ObIcon(path: String, width: Float, height: Float, color: Color, lineWidth: Float, modifier: Modifier = Modifier,
                    viewBoxWidth: Float = 24f, viewBoxHeight: Float = 24f, filled: Boolean = false) {
    val shapes = remember(path) { path.split("|").map(ObSvgPath::segment) }
    Canvas(modifier.size(width.dp, height.dp)) {
        val factor = min(size.width / viewBoxWidth, size.height / viewBoxHeight)
        scale(factor, factor, pivot = Offset.Zero) {
            shapes.forEach { shape ->
                if (filled) drawPath(shape, color)
                else drawPath(shape, color, style = Stroke(lineWidth, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
    }
}

/**
 * SVG `d` parser covering the commands the prototype's icon set uses: M/L/H/V/C/S/Q/T/A/Z and
 * their relative forms, with true elliptical arcs and flag digits written without separators.
 * Same algorithm as iOS `NovaOBSVGParser`, so both platforms draw identical geometry.
 */
internal object ObSvgPath {
    fun segment(segment: String): Path {
        if (segment.startsWith("circle:")) {
            val parts = segment.removePrefix("circle:").split(",").mapNotNull { it.trim().toFloatOrNull() }
            if (parts.size != 3) return Path()
            return Path().apply { addOval(Rect(parts[0] - parts[2], parts[1] - parts[2], parts[0] + parts[2], parts[1] + parts[2])) }
        }
        return parse(segment)
    }

    fun parse(d: String): Path {
        val path = Path()
        var current = Offset.Zero
        var start = Offset.Zero
        var lastControl: Offset? = null
        var lastQuadControl: Offset? = null
        val numbers = mutableListOf<Float>()
        var command = 'M'
        val token = StringBuilder()

        fun flush() {
            token.toString().toFloatOrNull()?.let(numbers::add)
            token.setLength(0)
        }

        fun resolve(x: Float, y: Float, relative: Boolean) = if (relative) Offset(current.x + x, current.y + y) else Offset(x, y)

        fun apply() {
            val relative = command.isLowerCase()
            val kind = command.lowercaseChar()
            if (numbers.isEmpty() && kind != 'z') { numbers.clear(); return }
            when (kind) {
                'm' -> {
                    var index = 0
                    while (index + 1 < numbers.size) {
                        val point = resolve(numbers[index], numbers[index + 1], relative)
                        if (index == 0) { path.moveTo(point.x, point.y); start = point } else path.lineTo(point.x, point.y)
                        current = point
                        index += 2
                    }
                    lastControl = null; lastQuadControl = null
                }
                'l' -> {
                    var index = 0
                    while (index + 1 < numbers.size) {
                        val point = resolve(numbers[index], numbers[index + 1], relative)
                        path.lineTo(point.x, point.y)
                        current = point
                        index += 2
                    }
                    lastControl = null; lastQuadControl = null
                }
                'h' -> {
                    numbers.forEach { value ->
                        current = Offset(if (relative) current.x + value else value, current.y)
                        path.lineTo(current.x, current.y)
                    }
                    lastControl = null; lastQuadControl = null
                }
                'v' -> {
                    numbers.forEach { value ->
                        current = Offset(current.x, if (relative) current.y + value else value)
                        path.lineTo(current.x, current.y)
                    }
                    lastControl = null; lastQuadControl = null
                }
                'c' -> {
                    var index = 0
                    while (index + 5 < numbers.size) {
                        val c1 = resolve(numbers[index], numbers[index + 1], relative)
                        val c2 = resolve(numbers[index + 2], numbers[index + 3], relative)
                        val end = resolve(numbers[index + 4], numbers[index + 5], relative)
                        path.cubicTo(c1.x, c1.y, c2.x, c2.y, end.x, end.y)
                        current = end
                        lastControl = c2
                        index += 6
                    }
                    lastQuadControl = null
                }
                's' -> {
                    var index = 0
                    while (index + 3 < numbers.size) {
                        val c1 = lastControl?.let { Offset(2 * current.x - it.x, 2 * current.y - it.y) } ?: current
                        val c2 = resolve(numbers[index], numbers[index + 1], relative)
                        val end = resolve(numbers[index + 2], numbers[index + 3], relative)
                        path.cubicTo(c1.x, c1.y, c2.x, c2.y, end.x, end.y)
                        current = end
                        lastControl = c2
                        index += 4
                    }
                    lastQuadControl = null
                }
                'q' -> {
                    var index = 0
                    while (index + 3 < numbers.size) {
                        val control = resolve(numbers[index], numbers[index + 1], relative)
                        val end = resolve(numbers[index + 2], numbers[index + 3], relative)
                        path.quadraticTo(control.x, control.y, end.x, end.y)
                        current = end
                        lastQuadControl = control
                        index += 4
                    }
                    lastControl = null
                }
                't' -> {
                    var index = 0
                    while (index + 1 < numbers.size) {
                        val control = lastQuadControl?.let { Offset(2 * current.x - it.x, 2 * current.y - it.y) } ?: current
                        val end = resolve(numbers[index], numbers[index + 1], relative)
                        path.quadraticTo(control.x, control.y, end.x, end.y)
                        current = end
                        lastQuadControl = control
                        index += 2
                    }
                    lastControl = null
                }
                'a' -> {
                    var index = 0
                    while (index + 6 < numbers.size) {
                        val end = resolve(numbers[index + 5], numbers[index + 6], relative)
                        appendArc(path, current, end, abs(numbers[index]), abs(numbers[index + 1]), numbers[index + 2],
                            numbers[index + 3] != 0f, numbers[index + 4] != 0f)
                        current = end
                        index += 7
                    }
                    lastControl = null; lastQuadControl = null
                }
                'z' -> {
                    path.close()
                    current = start
                    lastControl = null; lastQuadControl = null
                }
            }
            numbers.clear()
        }

        for (character in d) {
            when {
                character.isLetter() && character != 'e' -> { flush(); apply(); command = character }
                character == ',' || character == ' ' -> flush()
                character == '-' && token.isNotEmpty() && token.last() != 'e' -> { flush(); token.append('-') }
                character == '.' && token.contains('.') -> { flush(); token.append('.') }
                isArcFlagPosition(command, numbers.size, token) && character.isDigit() ->
                    // Arc flags are single digits usually written without a separator
                    // ("a4 4 0 018 0"), so they must not merge into the following coordinate.
                    numbers.add(if (character == '0') 0f else 1f)
                else -> token.append(character)
            }
        }
        flush(); apply()
        return path
    }

    /** Positions 3 and 4 of every 7-value arc set are the large-arc / sweep flags. */
    private fun isArcFlagPosition(command: Char, count: Int, token: StringBuilder): Boolean {
        if ((command != 'a' && command != 'A') || token.isNotEmpty()) return false
        val position = count % 7
        return position == 3 || position == 4
    }

    /** Endpoint-to-centre arc conversion (SVG implementation notes F.6), emitted as ≤90° cubics. */
    private fun appendArc(path: Path, p0: Offset, p1: Offset, rx: Float, ry: Float, rotation: Float, largeArc: Boolean, sweep: Boolean) {
        if (rx <= 0f || ry <= 0f) { path.lineTo(p1.x, p1.y); return }
        if (abs(p0.x - p1.x) < 1e-6f && abs(p0.y - p1.y) < 1e-6f) return
        val phi = rotation * PI.toFloat() / 180f
        val cosPhi = cos(phi); val sinPhi = sin(phi)
        val dx = (p0.x - p1.x) / 2; val dy = (p0.y - p1.y) / 2
        val x1 = cosPhi * dx + sinPhi * dy
        val y1 = -sinPhi * dx + cosPhi * dy
        var radiusX = rx; var radiusY = ry
        val lambda = (x1 * x1) / (radiusX * radiusX) + (y1 * y1) / (radiusY * radiusY)
        if (lambda > 1) { radiusX *= sqrt(lambda); radiusY *= sqrt(lambda) }
        val numerator = max(0f, radiusX * radiusX * radiusY * radiusY - radiusX * radiusX * y1 * y1 - radiusY * radiusY * x1 * x1)
        val denominator = radiusX * radiusX * y1 * y1 + radiusY * radiusY * x1 * x1
        val factor = if (denominator == 0f) 0f else sqrt(numerator / denominator) * (if (largeArc == sweep) -1f else 1f)
        val cx1 = factor * radiusX * y1 / radiusY
        val cy1 = -factor * radiusY * x1 / radiusX
        val cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        val cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

        fun angle(ux: Float, uy: Float, vx: Float, vy: Float): Float {
            val length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            if (length <= 0f) return 0f
            val value = ((ux * vx + uy * vy) / length).coerceIn(-1f, 1f)
            return (if (ux * vy - uy * vx < 0) -1f else 1f) * acos(value)
        }

        val startAngle = angle(1f, 0f, (x1 - cx1) / radiusX, (y1 - cy1) / radiusY)
        var sweepAngle = angle((x1 - cx1) / radiusX, (y1 - cy1) / radiusY, (-x1 - cx1) / radiusX, (-y1 - cy1) / radiusY)
        if (!sweep && sweepAngle > 0) sweepAngle -= 2 * PI.toFloat()
        if (sweep && sweepAngle < 0) sweepAngle += 2 * PI.toFloat()

        val segments = max(1, ceil(abs(sweepAngle) / (PI.toFloat() / 2)).toInt())
        val delta = sweepAngle / segments
        val alpha = 4f / 3f * tan(delta / 4)
        var theta = startAngle
        var from = p0
        repeat(segments) {
            val theta2 = theta + delta
            val cosT1 = cos(theta); val sinT1 = sin(theta)
            val cosT2 = cos(theta2); val sinT2 = sin(theta2)
            val end = Offset(cosPhi * radiusX * cosT2 - sinPhi * radiusY * sinT2 + cx, sinPhi * radiusX * cosT2 + cosPhi * radiusY * sinT2 + cy)
            val d1 = Offset(-cosPhi * radiusX * sinT1 - sinPhi * radiusY * cosT1, -sinPhi * radiusX * sinT1 + cosPhi * radiusY * cosT1)
            val d2 = Offset(-cosPhi * radiusX * sinT2 - sinPhi * radiusY * cosT2, -sinPhi * radiusX * sinT2 + cosPhi * radiusY * cosT2)
            path.cubicTo(from.x + alpha * d1.x, from.y + alpha * d1.y, end.x - alpha * d2.x, end.y - alpha * d2.y, end.x, end.y)
            from = end
            theta = theta2
        }
    }
}
