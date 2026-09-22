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
                           val progressCompleted: Int = 0, val progressTotal: Int = 8)
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
                        onAssistant: () -> Unit, showsPhotoCapture: Boolean = true, showsAssistant: Boolean = true,
                        tracking: (@Composable () -> Unit)? = null, footer: (@Composable () -> Unit)? = null) {
    val muted = NovaColorToken.textMuted.color()
    val accentInk = NovaColorToken.accentInk.color()
    val wide = LocalDensity.current.fontScale >= 1.5f
    Column(Modifier.fillMaxSize().background(NovaColorToken.canvas.color()).verticalScroll(rememberScrollState())
        .testTag("nova.home.scroll").padding(bottom = 122.dp)) {
        NovaWelcomeCard(data, showsAssistant, onAssistant, Modifier.padding(horizontal = 20.dp).padding(top = 10.dp, bottom = 20.dp))
        Row(Modifier.padding(horizontal = 20.dp).padding(bottom = 9.dp), verticalAlignment = Alignment.CenterVertically) {
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
                    Column(Modifier.width(198.dp).height(130.dp).clip(RoundedCornerShape(18.dp)).novaControlBackground(18.dp)
                        .novaRowPress { onNavigate(NovaDestination.analyses) }.testTag("nova.home.analysis.${analysis.id}")
                        .padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("photo.on.rectangle.angled", 18.dp, tint = accentInk)
                            Spacer(Modifier.weight(1f))
                            NovaIcon("chevron.right", 13.dp)
                        }
                        NovaText(analysis.title, style = NovaTypeToken.bodyStrong, maxLines = 2)
                        NovaText(listOf(analysis.companyName, analysis.createdOn).filter { it.isNotEmpty() }.joinToString(" · "),
                            style = NovaTypeToken.metaQuiet, color = muted, maxLines = 1)
                    }
                }
            }
        }
        if (tracking != null) Box(Modifier.padding(horizontal = 20.dp).padding(top = 22.dp)) { tracking() }
        if (footer != null) Box(Modifier.padding(horizontal = 16.dp).padding(top = 22.dp)) { footer() }
    }
}

@Composable
private fun NovaWelcomeCard(data: NovaDashboardData, showsAssistant: Boolean, onAssistant: () -> Unit, modifier: Modifier) {
    val surface = NovaColorToken.surface.color()
    val dark = LocalNovaDark.current
    val accent = NovaColorToken.accent.color()
    val shape = RoundedCornerShape(22.dp)
    Box(modifier.fillMaxWidth().clip(shape)
        .background(Brush.linearGradient(listOf(surface, surface.copy(alpha = 0.92f), accent.copy(alpha = if (dark) 0.42f else 0.28f))), shape)
        .border(1.dp, NovaColorToken.border.color(), shape)) {
        NovaSafetyIconPattern(Modifier.matchParentSize())
        val greeting = @Composable { m: Modifier ->
            Column(m, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("helmet", 18.dp)
                    NovaSizedText("Merhaba, ${data.firstName}", 15.5f, FontWeight.Bold)
                }
                NovaText(data.summaryMessage ?: data.openCount?.let { "Bugün $it açık uygunsuzluk var." } ?: "Özet yükleniyor…",
                    style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color())
            }
        }
        val assistant = @Composable {
            Row(Modifier.heightIn(min = 44.dp).clip(CircleShape).background(NovaColorToken.surfaceMuted.color(), CircleShape)
                .novaRowPress(onClick = onAssistant).testTag("nova.home.assistant").padding(horizontal = 15.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("sparkle", 14.dp)
                NovaSizedText("AI Asistan", 13.5f)
            }
        }
        if (novaFontScaleIsAccessibility()) Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            greeting(Modifier)
            if (showsAssistant) assistant()
        } else Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            greeting(Modifier.weight(1f))
            if (showsAssistant) assistant()
        }
    }
}

/** Quiet decorative texture behind the greeting. */
@Composable
private fun NovaSafetyIconPattern(modifier: Modifier) {
    val items = listOf(
        listOf("eyeglasses", 27, 0.16, 0.78, 0.25), listOf("person.crop.square", 40, 0.11, 0.93, 0.22),
        listOf("hand.raised.fill", 23, 0.13, 0.70, 0.70), listOf("shield.fill", 30, 0.10, 0.87, 0.72),
        listOf("waveform.path.ecg", 22, 0.12, 0.58, 0.36), listOf("wrench.and.screwdriver.fill", 19, 0.11, 0.99, 0.48),
        listOf("cross.case.fill", 18, 0.12, 0.62, 0.86))
    val ink = NovaColorToken.onDark.color()
    BoxWithConstraints(modifier.clearAndSetSemantics {}) {
        items.forEach { (symbol, size, opacity, x, y) ->
            val s = (size as Int).dp
            NovaIcon(symbol as String, s, Modifier.offset(maxWidth * (x as Double).toFloat() - s / 2, maxHeight * (y as Double).toFloat() - s / 2),
                tint = ink.copy(alpha = (opacity as Double).toFloat()))
        }
    }
}

@Composable
private fun NovaCaptureCard(onPhoto: () -> Unit, onManual: () -> Unit, modifier: Modifier) {
    val accent = NovaColorToken.accent.color()
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).novaControlBackground(26.dp).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText("Yeni kayıt", Modifier.background(NovaColorToken.surfaceMuted.color(), CircleShape)
                .padding(horizontal = 12.dp, vertical = 6.dp), NovaTypeToken.meta, NovaColorToken.text.color())
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.clearAndSetSemantics {}) {
                listOf(1f, 0.45f, 0.2f).forEach { Box(Modifier.size(6.dp).background(accent.copy(alpha = it), CircleShape)) }
            }
        }
        // Both creation methods answer the same question and share one hierarchy.
        val photo = @Composable { m: Modifier -> NovaAddActionCard("Fotoğraftan analiz", "Fotoğraf seç veya çek", "camera", "nova.home.photo", m, onPhoto) }
        val manual = @Composable { m: Modifier -> NovaAddActionCard("Elle uygunsuzluk", "Bilgileri adım adım gir", "square.and.pencil", "nova.home.addFinding", m, onManual) }
        if (novaFontScaleIsAccessibility()) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            photo(Modifier.fillMaxWidth()); manual(Modifier.fillMaxWidth())
        } else Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.height(IntrinsicSize.Max)) {
            photo(Modifier.weight(1f).fillMaxHeight()); manual(Modifier.weight(1f).fillMaxHeight())
        }
    }
}

@Composable
private fun NovaAddActionCard(title: String, detail: String, symbol: String, tag: String, modifier: Modifier, onClick: () -> Unit) {
    val accentInk = NovaColorToken.accentInk.color()
    val shape = RoundedCornerShape(18.dp)
    Column(modifier.heightIn(min = 126.dp).clip(shape).background(NovaColorToken.surfaceMuted.color(), shape)
        .border(1.dp, NovaColorToken.border.color(), shape).novaRowPress(onClick = onClick).testTag(tag).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp)) {
        NovaIcon(symbol, 23.dp, tint = accentInk)
        NovaText(title, style = NovaTypeToken.bodyStrong)
        NovaText(detail, style = NovaTypeToken.metaQuiet)
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText("Başla", Modifier.weight(1f), NovaTypeToken.meta, accentInk)
            NovaIcon("arrow.right", 13.dp)
        }
    }
}

/** Company list (iOS `NovaCompaniesScreen`), with the setup progress per company. */
@Composable
fun NovaCompaniesScreen(companies: List<NovaCompanyItem>, isLoading: Boolean = false, error: String? = null,
                        onSelect: (String) -> Unit, onBack: () -> Unit, onRetry: () -> Unit, isOwnedList: Boolean = false,
                        onCreate: (() -> Unit)? = null) {
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
                    filtered.forEachIndexed { index, company -> NovaCompanyRow(company, Modifier.novaRowEntrance(index)) { onSelect(company.id) } }
                }
            }
        }
    }
}

@Composable
private fun NovaCompanyRow(company: NovaCompanyItem, modifier: Modifier, onClick: () -> Unit) {
    val total = company.progressTotal.coerceAtLeast(1)
    val done = company.progressCompleted.coerceIn(0, total)
    Row(modifier.fillMaxWidth().heightIn(min = 82.dp).clip(RoundedCornerShape(22.dp)).novaControlBackground(22.dp)
        .novaRowPress(onClick = onClick).testTag("nova.company.${company.id}").padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        Box(Modifier.size(38.dp).background(Brush.linearGradient(listOf(Color(1f, 0.42f, 0.37f), Color(0.89f, 0.2f, 0.16f))),
            RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
            NovaText(novaInitialsOf(company.name), style = NovaTypeToken.cardTitle, color = Color.White)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText(company.name, style = NovaTypeToken.cardTitle)
            NovaText(company.detail, style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f).height(5.dp).background(NovaColorToken.surfaceMuted.color(), CircleShape)) {
                    Box(Modifier.fillMaxWidth(done.toFloat() / total).fillMaxHeight().background(NovaColorToken.accent.color(), CircleShape))
                }
                NovaText("$done/$total", style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color())
            }
        }
        NovaIcon("chevron.right", 14.dp, tint = NovaColorToken.borderStrong.color())
    }
}

