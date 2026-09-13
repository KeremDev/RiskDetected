package com.riskdetectedan.core.designsystem.isg

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.ui.res.vectorResource
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale

/** Authorized account-scoped records are injected by the host; no fake production counts. */
data class NovaCompanyItem(val id: String, val name: String, val detail: String)
data class NovaMetricItem(val id: String, val value: String, val label: String, val footer: String,
                          val icon: ImageVector, val tone: NovaColorToken, val destination: NovaDestination)
data class NovaDashboardData(val firstName: String, val openCount: Int?, val metrics: List<NovaMetricItem>,
                             val activity: String?, val trainingMessage: String, val recentFindings: List<NovaRecentFinding> = emptyList())
data class NovaRecentFinding(val id: String, val companyName: String, val thumbnail: ImageBitmap? = null)

internal fun filterNovaCompanies(companies: List<NovaCompanyItem>, query: String): List<NovaCompanyItem> {
    val locale = Locale.forLanguageTag("tr-TR")
    val needle = query.trim().lowercase(locale)
    return if (needle.isEmpty()) companies else companies.filter { "${it.name} ${it.detail}".lowercase(locale).contains(needle) }
}

@Composable
internal fun NovaSizeText(text: String, size: Float, weight: FontWeight = FontWeight.SemiBold,
                         color: Color = NovaColorToken.text.color(), modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) {
    Text(text, modifier, color, style = NovaTypeToken.body.textStyle().copy(fontSize = size.sp, lineHeight = (size * 1.25f).sp, fontWeight = weight), maxLines = maxLines)
}

@Composable
private fun NovaScreenCard(modifier: Modifier = Modifier, radius: Int = 22, padding: Int = 16, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.background(NovaColorToken.surface.color(), RoundedCornerShape(radius.dp)).padding(padding.dp), content = content)
}

@Composable
fun NovaDashboardScreen(data: NovaDashboardData, onNavigate: (NovaDestination) -> Unit, onPhoto: () -> Unit, onAssistant: () -> Unit,
                         onFinding: ((String) -> Unit)? = null) {
    val expanded = LocalDensity.current.fontScale >= 1.5f
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).testTag("nova.home.scroll").padding(bottom = 122.dp)) {
        NovaScreenCard(Modifier.padding(horizontal = 20.dp).fillMaxWidth()) {
            @Composable fun Greeting(modifier: Modifier = Modifier) {
                Column(modifier) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        Icon(androidx.compose.ui.res.painterResource(com.riskdetectedan.core.designsystem.R.drawable.nova_helmet), null, Modifier.size(18.dp), tint = NovaColorToken.text.color())
                        NovaSizeText("Merhaba, ${data.firstName}", 15.5f, FontWeight.Bold)
                    }
                    NovaText(data.openCount?.let { "Bugün $it açık uygunsuzluk var." } ?: "Özet yükleniyor…", Modifier.padding(top = 3.dp), NovaTypeToken.metaQuiet, NovaColorToken.textMuted.color())
                }
            }
            @Composable fun Assistant() {
                Row(Modifier.heightIn(min = 48.dp).background(NovaColorToken.surfaceMuted.color(), CircleShape)
                    .clickable(role = Role.Button, onClick = onAssistant).testTag("nova.home.assistant").padding(horizontal = 15.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    NovaGlyph(Icons.Outlined.AutoAwesome, null, Modifier.size(14.dp))
                    NovaSizeText("AI Asistan", 13.5f)
                }
            }
            if (expanded) { Greeting(); Spacer(Modifier.height(12.dp)); Assistant() }
            else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) { Greeting(Modifier.weight(1f)); Assistant() }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 20.dp, bottom = 9.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            NovaText("Özet", style = NovaTypeToken.sectionTitle)
            NovaText("Bu ay", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            data.metrics.forEach { metric ->
                Column(Modifier.width(if (expanded) 160.dp else 86.dp).heightIn(min = 86.dp)
                    .background(NovaColorToken.surface.color(), RoundedCornerShape(18.dp))
                    .clickable(role = Role.Button) { onNavigate(metric.destination) }.testTag("nova.metric.${metric.id}").padding(horizontal = 10.dp, vertical = 11.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        NovaGlyph(metric.icon, null, Modifier.size(15.dp), metric.tone.color())
                        NovaSizeText(metric.value, 19f, FontWeight.ExtraBold)
                    }
                    NovaSizeText(metric.label, 10f, FontWeight.Medium, NovaColorToken.textMuted.color(), Modifier.padding(top = 3.dp).heightIn(min = 24.dp), maxLines = 2)
                    NovaSizeText(metric.footer, 9.5f, FontWeight.Bold, if (metric.id == "open") metric.tone.color() else NovaColorToken.textMuted.color(), maxLines = 1)
                }
            }
        }
        NovaScreenCard(Modifier.padding(horizontal = 20.dp).padding(top = 18.dp).fillMaxWidth(), radius = 24, padding = 12) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                NovaText("Canlı Akış", style = NovaTypeToken.sectionTitle)
                TextButton(onClick = { onNavigate(NovaDestination.notifications) }, modifier = Modifier.height(32.dp), contentPadding = PaddingValues(horizontal = 4.dp)) {
                    NovaText("Tümü", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                    NovaGlyph(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.size(14.dp), NovaColorToken.accentInk.color())
                }
            }
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(enabled = data.activity != null, role = Role.Button) { onNavigate(NovaDestination.notifications) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaGlyph(Icons.Outlined.Business, null, Modifier.size(16.dp), NovaColorToken.statusInfoDot.color())
                NovaSizeText(data.activity ?: "Henüz yeni etkinlik yok.", 11.5f, color = NovaColorToken.textSecondary.color(), modifier = Modifier.weight(1f), maxLines = 1)
                NovaGlyph(Icons.Outlined.ChevronRight, null, Modifier.size(13.dp), NovaColorToken.textTertiary.color())
            }
        }
        NovaScreenCard(Modifier.padding(horizontal = 20.dp).padding(top = 12.dp).fillMaxWidth(), radius = 26, padding = 18) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                NovaText("Yeni kayıt", Modifier.background(NovaColorToken.surfaceMuted.color(), CircleShape).padding(horizontal = 12.dp, vertical = 6.dp), NovaTypeToken.meta, NovaColorToken.textSecondary.color())
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    listOf(1f, .45f, .2f).forEach { Box(Modifier.size(6.dp).background(NovaColorToken.accent.color().copy(alpha = it), CircleShape)) }
                }
            }
            val photoBorder = NovaColorToken.borderStrong.color()
            Box(Modifier.padding(top = 12.dp).fillMaxWidth().heightIn(min = 118.dp).clip(RoundedCornerShape(20.dp))
                .background(NovaColorToken.canvasSheet.color()).drawBehind {
                    drawRoundRect(photoBorder, cornerRadius = CornerRadius(20.dp.toPx()), style = Stroke(1.6.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
                }.clickable(role = Role.Button, onClick = onPhoto).testTag("nova.home.photo"), contentAlignment = Alignment.Center) {
                NovaPhotoBackdrop(Modifier.matchParentSize())
                Column(Modifier.padding(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterVertically)) {
                Box(Modifier.size(46.dp), contentAlignment = Alignment.Center) {
                    NovaGlyph(Icons.Outlined.PhotoCamera, null, Modifier.size(22.dp))
                    NovaGlyph(Icons.Outlined.Add, null, Modifier.align(Alignment.BottomEnd).size(15.dp), NovaColorToken.accent.color())
                }
                NovaText("Fotoğraf çek veya galeriden seç", style = NovaTypeToken.meta, color = NovaColorToken.textTertiary.color())
                }
            }
            Row(Modifier.padding(top = 14.dp).fillMaxWidth().heightIn(min = 54.dp).background(NovaColorToken.accent.color(), CircleShape)
                .clickable(role = Role.Button) { onNavigate(NovaDestination.newFinding) }.testTag("nova.home.addFinding"),
                horizontalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                NovaGlyph(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.size(20.dp), Color.White)
                NovaText("Uygunsuzluk Ekle", style = NovaTypeToken.button, color = Color.White)
            }
        }
        Row(Modifier.padding(horizontal = 18.dp).padding(top = 22.dp).fillMaxWidth().heightIn(min = 60.dp)
            .background(NovaColorToken.surface.color(), RoundedCornerShape(24.dp)).clickable(role = Role.Button) { onNavigate(NovaDestination.training) }
            .testTag("nova.home.training").padding(horizontal = 14.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaGlyph(Icons.Outlined.ThumbUp, null, Modifier.size(22.dp), NovaColorToken.accent.color())
            Column(Modifier.weight(1f)) {
                NovaText("Eğitim ve Takip", style = NovaTypeToken.cardTitle)
                NovaSizeText(data.trainingMessage, 11f, FontWeight.Normal, NovaColorToken.textSecondary.color())
            }
            NovaGlyph(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp))
        }
        Row(Modifier.padding(horizontal = 20.dp).padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaGlyph(Icons.Outlined.FilterList, null, Modifier.size(20.dp), NovaColorToken.accentInk.color())
            NovaText("Son Uygunsuzluklar", Modifier.weight(1f).padding(start = 10.dp), NovaTypeToken.screenTitle)
            TextButton(onClick = { onNavigate(NovaDestination.findings) }) { NovaText("Tümü", style = NovaTypeToken.meta) }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            data.recentFindings.forEach { finding ->
                Column(Modifier.width(74.dp).clickable(enabled = onFinding != null, role = Role.Button) { onFinding?.invoke(finding.id) }.testTag("nova.recent.${finding.id}"),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val ring = NovaColorToken.statusInfoDot.color()
                    Box(Modifier.size(66.dp).drawBehind { drawCircle(ring, style = Stroke(3.dp.toPx())) }.padding(3.dp).clip(CircleShape), contentAlignment = Alignment.Center) {
                        if (finding.thumbnail != null) Image(finding.thumbnail, null, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                        else NovaGlyph(Icons.Outlined.PhotoCamera, null, Modifier.size(22.dp))
                    }
                    NovaSizeText(finding.companyName, 11.5f, color = NovaColorToken.textMuted.color(), maxLines = 1)
                }
            }
        }
    }
}

/** Source PhotoBackdrop.tsx icon collage; decorative only, no colored icon tiles. */
@Composable private fun NovaPhotoBackdrop(modifier: Modifier) {
    val motifs = listOf(
        listOf(30f, .06f, 16f, 12f, -14f, 0f), listOf(20f, .075f, 62f, 62f, 8f, 1f),
        listOf(40f, .045f, 24f, 66f, 6f, 1f), listOf(22f, .07f, 108f, 16f, 12f, 0f),
        listOf(16f, .085f, 148f, 74f, -8f, 1f), listOf(34f, .05f, 210f, 20f, -10f, 0f),
        listOf(24f, .07f, 262f, 66f, 14f, 1f), listOf(18f, .075f, 300f, 22f, -6f, 0f),
        listOf(28f, .05f, 246f, 8f, 18f, 0f), listOf(20f, .06f, 186f, 76f, -16f, 0f))
    BoxWithConstraints(modifier) {
        motifs.forEach { m ->
            Icon(androidx.compose.ui.graphics.vector.ImageVector.vectorResource(if (m[5] == 1f) com.riskdetectedan.core.designsystem.R.drawable.nova_backdrop_camera else com.riskdetectedan.core.designsystem.R.drawable.nova_backdrop_photo), null,
                Modifier.offset(x = maxWidth * (m[2] / 326f), y = maxHeight * (m[3] / 118f)).size(m[0].dp).rotate(m[4]).alpha(m[1]), tint = NovaColorToken.text.color())
        }
    }
}

@Composable
fun NovaCompaniesScreen(companies: List<NovaCompanyItem>, isLoading: Boolean = false, error: String? = null,
                         onSelect: (String) -> Unit, onBack: () -> Unit, onRetry: () -> Unit, isOwnedList: Boolean = false) {
    var query by rememberSaveable { mutableStateOf("") }
    val filtered = filterNovaCompanies(companies, query)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 122.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            IconButton(onClick = onBack) { NovaGlyph(Icons.Outlined.ChevronLeft, "Panele dön", Modifier.size(18.dp)) }
            Column {
                NovaText("Firmalar", style = NovaTypeToken.screenTitle)
                NovaText(if (isOwnedList) "${filtered.size} firma" else "${filtered.size} atanmış firma", style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color())
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).background(NovaColorToken.surface.color(), RoundedCornerShape(16.dp)).padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaGlyph(Icons.Outlined.Search, null, Modifier.size(18.dp), NovaColorToken.textPlaceholder.color())
            BasicTextField(query, { query = it }, Modifier.weight(1f).testTag("nova.companies.search").semantics { contentDescription = "Firma ara" },
                textStyle = NovaTypeToken.body.textStyle().copy(color = NovaColorToken.text.color()), singleLine = true,
                decorationBox = { inner -> if (query.isEmpty()) NovaText("Firma ara...", color = NovaColorToken.textPlaceholder.color()); inner() })
            if (query.isNotEmpty()) IconButton(onClick = { query = "" }, Modifier.testTag("nova.companies.clear")) { NovaGlyph(Icons.Outlined.Close, "Aramayı temizle", Modifier.size(16.dp)) }
        }
        when {
            isLoading -> Row(Modifier.padding(14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaGlyph(Icons.Outlined.HourglassEmpty, null, Modifier.size(20.dp)); NovaText("Firmalar yükleniyor")
            }
            error != null -> Column {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaGlyph(Icons.Outlined.ErrorOutline, null, Modifier.size(20.dp), NovaColorToken.statusDangerInk.color())
                    NovaText(error)
                }
                TextButton(onClick = onRetry) { NovaGlyph(Icons.Outlined.Refresh, null, Modifier.size(20.dp)); NovaText("Tekrar dene") }
            }
            filtered.isEmpty() -> Row(Modifier.padding(14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaGlyph(Icons.Outlined.Business, null, Modifier.size(20.dp))
                NovaText(if (query.isEmpty()) { if (isOwnedList) "Henüz firma eklenmedi." else "Hesabına atanmış firma yok." } else "Firma bulunamadı")
            }
            else -> filtered.forEach { company ->
                Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).background(NovaColorToken.surface.color(), RoundedCornerShape(22.dp))
                    .clickable(role = Role.Button) { onSelect(company.id) }.testTag("nova.company.${company.id}").padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                    Box(Modifier.size(38.dp).background(Color(0xFFF05245), RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
                        NovaText(novaInitials(company.name), style = NovaTypeToken.cardTitle, color = Color.White)
                    }
                    Column(Modifier.weight(1f)) {
                        NovaText(company.name, style = NovaTypeToken.cardTitle)
                        NovaText(company.detail, Modifier.padding(top = 3.dp), NovaTypeToken.meta, NovaColorToken.textMuted.color())
                    }
                    NovaGlyph(Icons.Outlined.ChevronRight, null, Modifier.size(13.dp), NovaColorToken.borderStrong.color())
                }
            }
        }
        TextButton(onClick = onBack) {
            NovaGlyph(Icons.Outlined.ChevronLeft, null, Modifier.size(16.dp), NovaColorToken.textMuted.color())
            NovaText("Panele dön", Modifier.padding(start = 8.dp), NovaTypeToken.meta, NovaColorToken.textMuted.color())
        }
    }
}
