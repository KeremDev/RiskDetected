package com.riskdetectedan.core.designsystem.isg

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.Locale

/** Authorized account-scoped records are injected by the host; no fake production counts. */
data class NovaCompanyItem(val id: String, val name: String, val detail: String,
                           val progressCompleted: Int = 0, val progressTotal: Int = 8, val logoPath: String? = null)

/** Loads one company's logo for the list row (iOS `NovaCompanyLogoLoader`); null keeps the initials. */
typealias NovaCompanyLogoLoader = suspend (companyId: String, logoPath: String?) -> androidx.compose.ui.graphics.ImageBitmap?
data class NovaMetricItem(val id: String, val value: String, val label: String, val footer: String,
                          val symbol: String, val tone: NovaColorToken, val destination: NovaDestination)
data class NovaRecentAnalysis(val id: String, val title: String, val companyName: String, val createdOn: String)
data class NovaDashboardData(val firstName: String, val openCount: Int?, val metrics: List<NovaMetricItem>,
                             val activity: String?, val trainingMessage: String,
                             val recentAnalyses: List<NovaRecentAnalysis> = emptyList(),
                             val summaryMessage: String? = null)

internal fun filterNovaCompanies(companies: List<NovaCompanyItem>, query: String): List<NovaCompanyItem> {
    val locale = Locale.forLanguageTag("tr-TR")
    val needle = query.trim().lowercase(locale)
    return if (needle.isEmpty()) companies else companies.filter { "${it.name} ${it.detail}".lowercase(locale).contains(needle) }
}

/** Legacy helper kept for the directory/personnel screens. */
@Composable
internal fun NovaSizeText(text: String, size: Float, weight: FontWeight = FontWeight.SemiBold,
                          color: Color = NovaColorToken.text.color(), modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) =
    NovaSizedText(text, size, weight, color, modifier, maxLines)

/**
 * Home (iOS `NovaDashboardScreen`). [tracking] and [footer] are host-owned
 * slots so the data-bound module tracking card and OSGB controls live inside
 * the same scroll surface without forking the layout.
 */
@Composable
fun NovaDashboardScreen(data: NovaDashboardData, onNavigate: (NovaDestination) -> Unit, onPhoto: () -> Unit,
                        showsPhotoCapture: Boolean = true,
                        analysisThumbnail: (suspend (String) -> androidx.compose.ui.graphics.ImageBitmap?)? = null,
                        onOpenAnalysis: ((String) -> Unit)? = null,
                        tracking: (@Composable () -> Unit)? = null, footer: (@Composable () -> Unit)? = null) {
    val muted = NovaColorToken.textMuted.color()
    val accentInk = NovaColorToken.accentInk.color()
    val wide = LocalDensity.current.fontScale >= 1.5f
    Column(Modifier.fillMaxSize().background(NovaColorToken.canvas.color()).verticalScroll(rememberScrollState())
        .testTag("nova.home.scroll").padding(bottom = 122.dp)) {
        Row(Modifier.padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaText("Özet", Modifier.weight(1f), NovaTypeToken.sectionTitle)
            NovaText("Güncel", style = NovaTypeToken.meta, color = muted)
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            data.metrics.forEach { metric ->
                NovaListStat(metric.label, metric.symbol, metric.value, Modifier.width(if (wide) 160.dp else 86.dp)
                    .testTag("nova.metric.${metric.id}")) { onNavigate(metric.destination) }
            }
        }
        if (showsPhotoCapture) NovaCaptureCard(onPhoto, { onNavigate(NovaDestination.newFinding) },
            Modifier.padding(horizontal = 20.dp).padding(bottom = 22.dp))
        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaIcon("line.3.horizontal.decrease", 20.dp, tint = accentInk)
            NovaText("Son Analizler", Modifier.weight(1f), NovaTypeToken.screenTitle)
            Box(Modifier.heightIn(min = 36.dp).novaRowPress { onNavigate(NovaDestination.analyses) }, contentAlignment = Alignment.Center) {
                NovaText("Tümü", style = NovaTypeToken.meta, color = muted)
            }
        }
        if (data.recentAnalyses.isEmpty()) {
            Row(Modifier.padding(horizontal = 20.dp).padding(top = 12.dp).fillMaxWidth().heightIn(min = 52.dp)
                .clip(RoundedCornerShape(18.dp)).novaControlBackground(18.dp)
                .novaRowPress { onNavigate(NovaDestination.newAnalysis) }.testTag("nova.home.analysis.empty")
                .padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaIcon("photo.on.rectangle.angled", 20.dp, tint = accentInk)
                NovaText("Henüz analiz yok · İlk analizi oluştur", Modifier.weight(1f), NovaTypeToken.meta)
                NovaIcon("chevron.right", 14.dp)
            }
        } else {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                data.recentAnalyses.forEach { analysis ->
                    NovaRecentAnalysisStory(analysis, analysisThumbnail) {
                        onOpenAnalysis?.invoke(analysis.id) ?: onNavigate(NovaDestination.analyses)
                    }
                }
            }
        }
        if (tracking != null) Box(Modifier.padding(horizontal = 20.dp).padding(top = 22.dp)) { tracking() }
        if (footer != null) Box(Modifier.padding(horizontal = 16.dp).padding(top = 22.dp)) { footer() }
    }
}

/** One recent analysis as a ringed photo circle (iOS `NovaRecentAnalysisStory`). */
@Composable
private fun NovaRecentAnalysisStory(analysis: NovaRecentAnalysis, loadPhoto: (suspend (String) -> androidx.compose.ui.graphics.ImageBitmap?)?,
                                    onOpen: () -> Unit) {
    var photo by remember(analysis.id) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    LaunchedEffect(analysis.id) { photo = loadPhoto?.invoke(analysis.id) }
    val dark = LocalNovaDark.current
    Box(Modifier.size(82.dp).clip(androidx.compose.foundation.shape.CircleShape).background(NovaColorToken.accentSoft.color())
        .border(1.25.dp, NovaColorToken.accent.color().copy(alpha = if (dark) 0.78f else 0.6f), androidx.compose.foundation.shape.CircleShape)
        .novaRowPress(onClick = onOpen).semantics { contentDescription = "${analysis.companyName}, ${analysis.createdOn}" }
        .testTag("nova.home.analysis.${analysis.id}"), contentAlignment = Alignment.Center) {
        val inner = Modifier.size(76.dp).clip(androidx.compose.foundation.shape.CircleShape)
            .border(1.dp, Color.White.copy(alpha = if (dark) 0.14f else 0.82f), androidx.compose.foundation.shape.CircleShape)
        val current = photo
        if (current != null) androidx.compose.foundation.Image(current, null, inner.graphicsLayer { scaleX = 1.55f; scaleY = 1.55f },
            contentScale = androidx.compose.ui.layout.ContentScale.Crop)
        else Box(inner.background(NovaColorToken.surfaceMuted.color()))
    }
}

/** The greeting banner: a tinted strip with a quiet PPE texture behind the text (iOS `welcome`). */
@Composable
private fun NovaWelcomeCard(data: NovaDashboardData, modifier: Modifier) {
    val surface = NovaColorToken.surface.color()
    val dark = LocalNovaDark.current
    val accent = NovaColorToken.accent.color()
    val shape = RoundedCornerShape(22.dp)
    val accessible = novaFontScaleIsAccessibility()
    BoxWithConstraints(modifier.fillMaxWidth().height(if (accessible) 92.dp else 72.dp).clip(shape)
        .background(Brush.linearGradient(listOf(surface, surface.copy(alpha = 0.94f), accent.copy(alpha = if (dark) 0.48f else 0.38f))), shape)
        .border(1.dp, NovaColorToken.border.color(), shape)) {
        NovaSafetyIconPattern(Modifier.matchParentSize())
        Column(Modifier.width(maxWidth * (if (accessible) 0.94f else 0.78f)).fillMaxHeight().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("helmet", 18.dp)
                NovaSizedText("Merhaba, ${data.firstName}", 15.5f, FontWeight.Bold, maxLines = 1)
            }
            NovaText(data.summaryMessage ?: data.openCount?.let { "Bugün $it açık uygunsuzluk var." } ?: "Özet yükleniyor…",
                style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color(), maxLines = 1)
        }
    }
}

private class NovaPatternItem(val symbol: String, val size: Float, val opacity: Float, val x: Float, val y: Float, val rotation: Float = 0f)

private val greetingPattern = listOf(
    NovaPatternItem("eyeglasses", 22f, 0.20f, 0.71f, 0.18f), NovaPatternItem("hardhat", 34f, 0.15f, 0.94f, 0.18f),
    NovaPatternItem("glove", 16f, 0.19f, 0.76f, 0.72f), NovaPatternItem("earmuffs", 27f, 0.16f, 0.94f, 0.72f),
    NovaPatternItem("safetyTape", 20f, 0.17f, 0.83f, 0.46f), NovaPatternItem("trafficCone", 15f, 0.18f, 0.69f, 0.87f),
    NovaPatternItem("exclamationmark.triangle.fill", 17f, 0.16f, 0.99f, 0.46f), NovaPatternItem("hardhat", 15f, 0.18f, 0.80f, 0.12f),
    NovaPatternItem("eyeglasses", 14f, 0.15f, 0.68f, 0.50f), NovaPatternItem("glove", 13f, 0.18f, 0.99f, 0.90f),
    NovaPatternItem("safetyTape", 16f, 0.15f, 0.82f, 0.91f), NovaPatternItem("trafficCone", 19f, 0.16f, 0.74f, 0.31f),
)

private val photoPattern = listOf(
    NovaPatternItem("hardhat", 27f, 0.22f, 0.11f, 0.16f, -12f), NovaPatternItem("eyeglasses", 24f, 0.19f, 0.39f, 0.11f, 8f),
    NovaPatternItem("earmuffs", 21f, 0.22f, 0.78f, 0.15f, 10f), NovaPatternItem("shield.fill", 17f, 0.18f, 0.94f, 0.32f, 9f),
    NovaPatternItem("glove", 23f, 0.20f, 0.08f, 0.40f, -8f), NovaPatternItem("trafficCone", 28f, 0.23f, 0.91f, 0.51f, 7f),
    NovaPatternItem("safetyTape", 20f, 0.18f, 0.12f, 0.67f, -8f), NovaPatternItem("hardhat", 17f, 0.16f, 0.35f, 0.58f, 12f),
    NovaPatternItem("hardhat", 22f, 0.20f, 0.61f, 0.70f, 12f), NovaPatternItem("eyeglasses", 23f, 0.18f, 0.89f, 0.84f, -10f),
    NovaPatternItem("hand.raised.fill", 18f, 0.17f, 0.66f, 0.34f, 12f), NovaPatternItem("exclamationmark.triangle.fill", 19f, 0.21f, 0.39f, 0.88f, -9f),
    NovaPatternItem("earmuffs", 18f, 0.17f, 0.54f, 0.17f, -6f), NovaPatternItem("safetyTape", 24f, 0.18f, 0.73f, 0.91f, 8f),
    NovaPatternItem("trafficCone", 17f, 0.17f, 0.10f, 0.91f, -7f), NovaPatternItem("shield.fill", 16f, 0.14f, 0.52f, 0.49f, 4f),
    NovaPatternItem("glove", 19f, 0.17f, 0.91f, 0.08f, 10f), NovaPatternItem("hardhat", 18f, 0.16f, 0.20f, 0.27f, -9f),
)

@Composable
private fun NovaPattern(items: List<NovaPatternItem>, color: Color, modifier: Modifier) {
    BoxWithConstraints(modifier.clearAndSetSemantics {}) {
        items.forEach { item ->
            val size = item.size.dp
            NovaSafetyPPEGlyph(item.symbol, item.size, color, Modifier.offset(maxWidth * item.x - size / 2, maxHeight * item.y - size / 2)
                .graphicsLayer { alpha = item.opacity; rotationZ = item.rotation })
        }
    }
}

/** Quiet decorative texture behind the greeting (iOS `NovaSafetyIconPattern`). */
@Composable
private fun NovaSafetyIconPattern(modifier: Modifier) = NovaPattern(greetingPattern, NovaColorToken.textSecondary.color(), modifier)

/** Light PPE collage on the photo-analysis card (iOS `NovaPhotoSafetyPattern`). */
@Composable
private fun NovaPhotoSafetyPattern(modifier: Modifier) = NovaPattern(photoPattern, NovaColorToken.textTertiary.color(), modifier)

/**
 * Small drawn PPE glyphs for the background collages (iOS `NovaSafetyPPEGlyph`): hard hat, ear muffs, cone and
 * barrier tape are drawn; the rest are the ordinary symbols.
 */
@Composable
private fun NovaSafetyPPEGlyph(symbol: String, size: Float, color: Color, modifier: Modifier = Modifier) {
    when (symbol) {
        "hardhat", "earmuffs", "trafficCone", "safetyTape" -> androidx.compose.foundation.Canvas(modifier.size(size.dp)) {
            val w = this.size.width; val h = this.size.height
            val stroke = androidx.compose.ui.graphics.drawscope.Stroke(maxOf(1.2.dp.toPx(), size * 0.055f * density),
                cap = androidx.compose.ui.graphics.StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round)
            fun path(build: androidx.compose.ui.graphics.Path.() -> Unit) = androidx.compose.ui.graphics.Path().apply(build)
            when (symbol) {
                "hardhat" -> {
                    val dome = path {
                        moveTo(w * 0.14f, h * 0.66f); lineTo(w * 0.86f, h * 0.66f); lineTo(w * 0.82f, h * 0.54f)
                        cubicTo(w * 0.74f, h * 0.12f, w * 0.26f, h * 0.12f, w * 0.18f, h * 0.54f); close()
                    }
                    drawPath(dome, color.copy(alpha = 0.12f))
                    drawPath(path {
                        moveTo(w * 0.14f, h * 0.66f); lineTo(w * 0.86f, h * 0.66f)
                        moveTo(w * 0.50f, h * 0.22f); lineTo(w * 0.50f, h * 0.60f)
                        moveTo(w * 0.08f, h * 0.73f); lineTo(w * 0.92f, h * 0.73f)
                    }, color, style = stroke)
                }
                "earmuffs" -> {
                    drawPath(path { moveTo(w * 0.19f, h * 0.69f); cubicTo(w * 0.12f, h * 0.02f, w * 0.88f, h * 0.02f, w * 0.81f, h * 0.69f) }, color, style = stroke)
                    listOf(0.19f, 0.81f).forEach { cx ->
                        val topLeft = androidx.compose.ui.geometry.Offset(w * cx - w * 0.12f, h * 0.65f - h * 0.19f)
                        val box = androidx.compose.ui.geometry.Size(w * 0.24f, h * 0.38f)
                        val radius = androidx.compose.ui.geometry.CornerRadius(size * 0.1f * density)
                        drawRoundRect(color.copy(alpha = 0.14f), topLeft, box, radius)
                        drawRoundRect(color, topLeft, box, radius, style = stroke)
                    }
                }
                "trafficCone" -> {
                    val cone = path {
                        moveTo(w * 0.47f, h * 0.12f); lineTo(w * 0.56f, h * 0.12f); lineTo(w * 0.78f, h * 0.78f); lineTo(w * 0.22f, h * 0.78f); close()
                    }
                    drawPath(cone, color.copy(alpha = 0.12f))
                    drawPath(cone, color, style = stroke)
                    drawPath(path { moveTo(w * 0.34f, h * 0.52f); lineTo(w * 0.66f, h * 0.52f) }, color, style = stroke)
                    drawRoundRect(color.copy(alpha = 0.2f), androidx.compose.ui.geometry.Offset(w * 0.12f, h * 0.81f),
                        androidx.compose.ui.geometry.Size(w * 0.76f, h * 0.12f), androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()))
                    drawPath(path { moveTo(w * 0.12f, h * 0.93f); lineTo(w * 0.88f, h * 0.93f) }, color, style = stroke)
                }
                else -> drawPath(path {
                    moveTo(w * 0.16f, h * 0.12f); lineTo(w * 0.16f, h * 0.88f); moveTo(w * 0.84f, h * 0.12f); lineTo(w * 0.84f, h * 0.88f)
                    moveTo(w * 0.16f, h * 0.36f); lineTo(w * 0.39f, h * 0.57f); lineTo(w * 0.61f, h * 0.39f); lineTo(w * 0.84f, h * 0.57f)
                }, color, style = androidx.compose.ui.graphics.drawscope.Stroke(stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round,
                    join = androidx.compose.ui.graphics.StrokeJoin.Round,
                    pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(size * 0.11f * density, size * 0.07f * density))))
            }
        }
        "glove" -> NovaIcon("hand.raised.fill", size.dp, modifier, tint = color)
        else -> NovaIcon(symbol, size.dp, modifier, tint = color)
    }
}

/** "Yeni kayıt": both creation routes side by side in a swipeable rail of equal cards (iOS `addActions`). */
@Composable
private fun NovaCaptureCard(onPhoto: () -> Unit, onManual: () -> Unit, modifier: Modifier) {
    val accessible = novaFontScaleIsAccessibility()
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText("Yeni kayıt", Modifier.weight(1f), NovaTypeToken.sectionTitle)
            Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("arrow.left.and.right", 10.dp, tint = NovaColorToken.textMuted.color())
                NovaSizedText("Kaydır", 10f, FontWeight.Medium, NovaColorToken.textMuted.color())
            }
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val width = maxWidth * (if (accessible) 0.86f else 0.68f)
            val height = if (accessible) 210.dp else 176.dp
            Row(Modifier.horizontalScroll(rememberScrollState()).testTag("nova.home.quickActions").padding(end = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                NovaAddActionCard("Fotoğraftan analiz", "Fotoğraf seç veya çek", "camera.fill", true, width, height, "nova.home.photo", onPhoto)
                NovaAddActionCard("Elle uygunsuzluk", "Bilgileri adım adım gir", "square.and.pencil", false, width, height, "nova.home.addFinding", onManual)
            }
        }
    }
}

@Composable
private fun NovaAddActionCard(title: String, detail: String, symbol: String, isPhoto: Boolean, width: androidx.compose.ui.unit.Dp,
                              height: androidx.compose.ui.unit.Dp, tag: String, onClick: () -> Unit) {
    val accent = NovaColorToken.accent.color()
    val accentInk = NovaColorToken.accentInk.color()
    val dash = NovaColorToken.borderStrong.color()
    val accessible = novaFontScaleIsAccessibility()
    val shape = RoundedCornerShape(18.dp)
    Box(Modifier.size(width, height).clip(shape).background(NovaColorToken.surface.color(), shape)
        .drawWithContent {
            drawContent()
            val inset = 0.6.dp.toPx()
            drawRoundRect(dash, androidx.compose.ui.geometry.Offset(inset, inset),
                androidx.compose.ui.geometry.Size(size.width - inset * 2, size.height - inset * 2),
                androidx.compose.ui.geometry.CornerRadius(18.dp.toPx()),
                style = androidx.compose.ui.graphics.drawscope.Stroke(1.2.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round,
                    pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
        }
        .novaRowPress(onClick = onClick).testTag(tag)) {
        if (isPhoto) NovaPhotoSafetyPattern(Modifier.matchParentSize())
        Column(Modifier.fillMaxSize().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Spacer(Modifier.weight(1f).heightIn(min = if (accessible) 48.dp else 78.dp))
            NovaText(title, style = NovaTypeToken.bodyStrong, maxLines = 2)
            NovaText(detail, style = NovaTypeToken.metaQuiet, maxLines = 2)
            Row(Modifier.padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaText("Başla", Modifier.weight(1f), NovaTypeToken.meta, accentInk)
                NovaIcon("arrow.right", 13.dp)
            }
        }
        val badge = if (isPhoto) 52.dp else 48.dp
        Box(Modifier.align(Alignment.Center).offset(y = if (accessible) (-42).dp else (-27).dp).size(badge)
            .background(accent.copy(alpha = 0.13f), CircleShape).border(1.dp, accent.copy(alpha = 0.34f), CircleShape),
            contentAlignment = Alignment.Center) {
            NovaIcon(symbol, if (isPhoto) 22.dp else 20.dp, tint = accentInk)
        }
    }
}

/** Company list (iOS `NovaCompaniesScreen`), with the setup progress per company. */
@Composable
fun NovaCompaniesScreen(companies: List<NovaCompanyItem>, isLoading: Boolean = false, error: String? = null,
                        onSelect: (String) -> Unit, onBack: () -> Unit, onRetry: () -> Unit, isOwnedList: Boolean = false,
                        onCreate: (() -> Unit)? = null, loadLogo: NovaCompanyLogoLoader? = null) {
    var query by rememberSaveable { mutableStateOf("") }
    val filtered = filterNovaCompanies(companies, query)
    val muted = NovaColorToken.textMuted.color()
    Column(Modifier.fillMaxSize().background(NovaColorToken.canvas.color()).verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaBackButton(onClick = onBack)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaSizedText("Firmalar", 20f, FontWeight.ExtraBold)
                NovaText(if (isOwnedList) "${filtered.size} firma" else "${filtered.size} atanmış firma",
                    style = NovaTypeToken.metaQuiet, color = muted)
            }
            if (onCreate != null) Row(Modifier.heightIn(min = 34.dp).widthIn(min = 116.dp).clip(CircleShape)
                .background(NovaColorToken.accent.color(), CircleShape).novaRowPress(onClick = onCreate)
                .testTag("nova.pilot.company.create").padding(horizontal = 15.dp),
                horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("plus", 13.dp, tint = NovaColorToken.onAccent.color())
                NovaText("Firma Ekle", style = NovaTypeToken.bodyStrong, color = NovaColorToken.onAccent.color())
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaControlBackground(16.dp).padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaIcon("magnifyingglass", 15.dp, tint = NovaColorToken.textPlaceholder.color())
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) NovaText("Firma ara...", color = NovaColorToken.textPlaceholder.color())
                BasicTextField(query, { query = it }, Modifier.fillMaxWidth().testTag("nova.companies.search")
                    .semantics { contentDescription = "Firma ara" }, singleLine = true,
                    textStyle = novaTextStyle(NovaTypeToken.body).copy(color = NovaColorToken.text.color()),
                    cursorBrush = SolidColor(NovaColorToken.text.color()))
            }
            if (query.isNotEmpty()) Box(Modifier.size(44.dp).novaPress(onClickLabel = "Aramayı temizle") { query = "" }
                .semantics { contentDescription = "Aramayı temizle" }.testTag("nova.companies.clear"), contentAlignment = Alignment.Center) {
                NovaIcon("xmark", 15.dp)
            }
        }
        when {
            isLoading -> Row(Modifier.padding(14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("hourglass", 16.dp); NovaText("Firmalar yükleniyor")
            }
            error != null -> Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("exclamationmark.triangle", 16.dp); NovaText("Firmalar alınamadı")
                }
                NovaText(error, style = NovaTypeToken.metaQuiet)
                Row(Modifier.heightIn(min = 44.dp).novaRowPress(onClick = onRetry).testTag("nova.companies.retry"),
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("arrow.clockwise", 16.dp); NovaText("Tekrar dene", style = NovaTypeToken.bodyStrong)
                }
            }
            filtered.isEmpty() -> Row(Modifier.padding(14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("building.2", 16.dp)
                NovaText(if (query.isNotBlank()) "Firma bulunamadı" else if (isOwnedList) "Henüz firma eklenmedi." else "Hesabına atanmış firma yok.")
            }
            else -> NovaListEntrance(filtered.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    filtered.forEachIndexed { index, company -> NovaCompanyRow(company, loadLogo, Modifier.novaRowEntrance(index)) { onSelect(company.id) } }
                }
            }
        }
    }
}

@Composable
private fun NovaCompanyRow(company: NovaCompanyItem, loadLogo: NovaCompanyLogoLoader?, modifier: Modifier, onClick: () -> Unit) {
    val total = company.progressTotal.coerceAtLeast(1)
    val done = company.progressCompleted.coerceIn(0, total)
    var logo by remember(company.id, company.logoPath) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    LaunchedEffect(company.id, company.logoPath, loadLogo) { logo = loadLogo?.invoke(company.id, company.logoPath) }
    // Early steps read amber, the middle orange and the finished stretch green (iOS `stepColor`).
    val warning = NovaColorToken.statusWarningDot.color()
    val accent = NovaColorToken.accent.color()
    fun stepColor(step: Int) = when { step < 2 -> warning; step < 5 -> Color(0.96f, 0.48f, 0.16f); else -> accent }
    Row(modifier.fillMaxWidth().heightIn(min = 82.dp).clip(RoundedCornerShape(22.dp)).novaControlBackground(22.dp)
        .novaRowPress(onClick = onClick).testTag("nova.company.${company.id}")
        .semantics { contentDescription = "${company.name}, ilerleme $done/$total" }.padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        val current = logo
        if (current != null) Box(Modifier.size(38.dp).background(NovaColorToken.surface.color(), RoundedCornerShape(13.dp))
            .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(13.dp)).padding(4.dp)) {
            androidx.compose.foundation.Image(current, "Firma logosu", Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Fit)
        } else Box(Modifier.size(38.dp).background(Brush.linearGradient(listOf(Color(1f, 0.42f, 0.37f), Color(0.89f, 0.2f, 0.16f))),
            RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
            NovaText(novaInitialsOf(company.name), style = NovaTypeToken.cardTitle, color = Color.White)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText(company.name, style = NovaTypeToken.cardTitle)
            NovaText(company.detail, style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.weight(1f).height(5.dp).clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    repeat(total) { step ->
                        Box(Modifier.weight(1f).fillMaxHeight().background(if (step < done) stepColor(step) else NovaColorToken.surfaceMuted.color(), CircleShape))
                    }
                }
                NovaText("$done/$total", style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color())
            }
        }
        NovaIcon("chevron.right", 14.dp, tint = NovaColorToken.borderStrong.color())
    }
}
