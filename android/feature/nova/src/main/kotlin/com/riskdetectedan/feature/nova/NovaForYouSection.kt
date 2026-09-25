package com.riskdetectedan.feature.nova

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.riskdetectedan.core.data.nova.NovaForYouCard
import com.riskdetectedan.core.data.nova.NovaForYouEvent
import com.riskdetectedan.core.data.nova.NovaForYouFeed
import com.riskdetectedan.core.data.nova.NovaForYouLayout
import com.riskdetectedan.core.data.nova.NovaForYouRotation
import com.riskdetectedan.core.data.nova.NovaFollowupPage
import com.riskdetectedan.core.data.nova.NovaListPreset
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** One company record a home card asked a list surface to open (iOS `NovaRecordTarget`). */
data class NovaRecordTarget(val id: String, val companyId: String)

/** The filter a home card put on a list, in the card's own words; removing it shows the whole list again (iOS `NovaListPresetChip`). */
@Composable
fun NovaListPresetChip(preset: NovaListPreset, onClear: () -> Unit) {
    val ink = NovaColorToken.accentInk.color()
    Row(Modifier.heightIn(min = 40.dp).clip(CircleShape).background(NovaColorToken.statusSuccessBg.color()).novaRowPress(onClick = onClear)
        .padding(horizontal = 12.dp, vertical = 6.dp).semantics { contentDescription = "${preset.title} filtresini kaldır" }
        .testTag("foryou.list.preset"), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon("sparkles", 11.dp, tint = ink)
        NovaText(preset.title, Modifier.weight(1f, fill = false), NovaTypeToken.micro, color = ink, maxLines = 2)
        NovaIcon("xmark", 8.dp, tint = ink)
    }
}

/** Words for one card (iOS `NovaForYouCopy`). An unknown key yields null and the card is skipped. */
internal data class NovaForYouCopy(val label: String, val title: String, val detail: String, val action: String, val symbol: String) {
    companion object {
        fun make(card: NovaForYouCard, kindTitle: (String) -> String = NovaFollowupPage::typeTitle, now: Instant = Instant.now()): NovaForYouCopy? {
            val p = card.params
            val count = (p.count ?: 0).toString()
            val total = (p.total ?: 0).toString()
            fun joined(vararg parts: String?) = parts.mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }.joinToString(" · ")
            val resume = "Kaldığın yerden devam edebilirsin."
            fun record(): String = joined(p.title, p.companyName).ifEmpty { resume }
            fun more(base: String): String = p.count?.takeIf { it > 1 }?.let { joined(base, "ve ${it - 1} kayıt daha") } ?: base
            fun delta(fallback: String): String = p.delta?.takeIf { it > 0 }?.let { "Önceki 7 güne göre $it daha fazla." } ?: fallback
            val sessions = "${p.sessions ?: 0} eğitim oturumu"
            val label = when (card.kind) {
                "continue" -> "Devam et"; "critical" -> "Dikkat"; "performance" -> "İlerleme"
                "discover" -> "Keşfet"; "motivation" -> "Başlangıç"; else -> return null
            }
            fun copy(title: String, detail: String, action: String, symbol: String) = NovaForYouCopy(label, title, detail, action, symbol)
            return when (card.key) {
                "continue.nonconformity_draft" -> copy("Taslak uygunsuzluk kaydın seni bekliyor", record(), "Devam et", "square.and.pencil")
                "continue.nonconformity_drafts" -> copy("$count taslak uygunsuzluk daha", "Listede $total taslağın tamamı açılır.", "Listeyi aç", "square.and.pencil")
                "continue.risk_drafts" -> copy("$count taslak risk değerlendirmesi daha", "Listede $total taslağın tamamı açılır.", "Listeyi aç", "shield")
                "continue.checklists_open" -> copy("$count açık kontrol listesi daha", "Listede $total açık listenin tamamı açılır.", "Listeyi aç", "checklist")
                "continue.drill_results" -> copy("$count tatbikat sonucu daha bekliyor", "Listede $total tatbikatın tamamı açılır.", "Listeyi aç", "flame")
                "continue.risk_draft" -> copy("Taslak risk değerlendirmene devam et", record(), "Devam et", "shield")
                "continue.checklist_open" -> copy("Kontrol listesini tamamla", record(), "Devam et", "checklist")
                "continue.drill_result" -> copy("Tatbikat sonucunu kaydet",
                    joined(p.companyName, "${p.dueOn?.let(NovaDay::label).orEmpty()} için planlanmıştı"), "Kaydet", "flame")
                "continue.training_draft" -> {
                    val edited = relative(p.updatedAt, now)?.let { "Son düzenleme: $it" }
                    copy("Başladığın eğitim kaydını tamamla", joined(p.companyName, edited).ifEmpty { resume }, "Devam et", "graduationcap")
                }
                "continue.company_create" -> copy("Firma eklemeye devam et", "Başladığın firma kaydı tamamlanmadı.", "Devam et", "building.2")
                "critical.expired" -> copy("$count kaydın süresi geçti", more(joined(p.kind?.let(kindTitle), p.companyName)), "İncele", "exclamationmark.circle")
                "critical.nonconformity_overdue" -> copy("$count uygunsuzluğun termini geçti", more(joined(p.title, p.companyName)), "İncele", "exclamationmark.triangle")
                "critical.soon" -> copy("$count kaydın süresi yaklaşıyor",
                    joined(p.kind?.let(kindTitle), p.companyName, p.dueOn?.let(NovaDay::label)), "Gör", "calendar.badge.clock")
                "performance.analyses_7d" -> copy("Son 7 günde $count analiz yaptın", delta("Çalışmalarına devam ediyorsun."), "Analizleri gör", "chart.bar")
                "performance.trained_people_7d" -> copy("Son 7 günde $count kişiye eğitim verdin", delta(sessions), "Eğitimleri gör", "person.3")
                "performance.nonconformities_7d" -> copy("Son 7 günde $count uygunsuzluk kaydettin",
                    delta("Takibini tek yerden yapabilirsin."), "Uygunsuzlukları gör", "list.bullet.clipboard")
                "performance.analyses_30d" -> copy("Son 30 günde $count analiz yaptın", "Son 30 günün analizleri listede açılır.", "Analizleri gör", "chart.bar")
                "performance.trained_people_30d" -> copy("Son 30 günde $count kişiye eğitim verdin", sessions, "Eğitimleri gör", "person.3")
                "performance.first_analysis" -> copy("İlk analizin hazır", "Bulguları inceleyip rapor alabilirsin.", "Analizi gör", "checkmark.seal")
                "performance.analyses_total" -> copy("Şimdiye kadar $count analiz yaptın", "Bütün analizlerin listede açılır.", "Analizleri gör", "chart.bar")
                "performance.trainings_total" -> copy("Şimdiye kadar $count eğitim kaydettin", "Bütün eğitim kayıtların listede açılır.", "Eğitimleri gör", "person.3")
                "performance.nonconformities_total" -> copy("Şimdiye kadar $count uygunsuzluk kaydettin", "Takibini tek yerden yapabilirsin.",
                    "Uygunsuzlukları gör", "list.bullet.clipboard")
                "discover.photo_analysis" -> copy("Fotoğraftan analizi keşfet", "Bir fotoğraf yükle, riskleri hızlıca tespit et.", "Dene", "camera")
                "discover.risk_wizard" -> copy("Risk Analizi Sihirbazını denedin mi?", "Adım adım ilerle, taslak risk değerlendirmeni hazırla.", "Hemen dene", "sparkles")
                "discover.nonconformity" -> copy("Uygunsuzluk takibini dene", "Sahada gördüğün eksikleri termin ve sorumluyla takip et.", "Kayıt oluştur", "exclamationmark.bubble")
                "discover.training" -> copy("İlk eğitim kaydını ekle", "Katılımcıları ve geçerlilik tarihlerini tek yerden yönet.", "Eğitim ekle", "graduationcap")
                "discover.equipment" -> copy("Periyodik kontrolleri takip et", "Ekipmanlarını ekle, kontrol tarihleri yaklaşınca gör.", "Ekipman ekle", "wrench.and.screwdriver")
                "discover.emergency_wizard" -> copy("Acil durum planını sihirbazla hazırla", "Birkaç soruyla düzenlenebilir bir taslak oluştur.", "Dene", "sparkles")
                "discover.checklist" -> copy("Kontrol listelerini dene", "Hazır listelerle saha denetimini hızlandır.", "Listeleri aç", "checklist")
                "discover.work_permit_forms" -> copy("Hazır çalışma izni formları", "Düzenlenebilir örnek formları incele ve indir.", "Formlara göz at", "doc.text")
                "discover.ppe_form" -> copy("KKD zimmet formu hazır", "Düzenlenebilir Word örneğini indir.", "Formu aç", "doc.text")
                "discover.statistics" -> copy("İstatistiklerini gör", "Analiz ve eğitim sayılarını aylık grafikte gör.", "Aç", "chart.bar")
                "discover.followup" -> copy("Evrak Takibi ile süreleri kaçırma", "Bütün belgelerin geçerlilik tarihleri tek listede.", "Aç", "calendar")
                "motivation.first_company" -> copy("İlk firmanı ekleyerek başla",
                    "Firma bilgilerini eklediğinde diğer modülleri daha verimli kullanabilirsin.", "Firma ekle", "building.2")
                "motivation.first_personnel" -> copy("Personel listeni oluştur",
                    "Eğitim kayıtları ve katılımcı listeleri personel üzerinden ilerler.", "Personel ekle", "person.badge.plus")
                "motivation.first_analysis" -> copy("İlk analizini yap", "Bir fotoğraf yükleyerek risk tespit etmeye başla.", "Başla", "camera")
                "motivation.today_analysis" -> copy("Yeni bir saha analiziyle devam et", "Fotoğraftan analizle hızlıca başlayabilirsin.", "Başla", "camera")
                "motivation.statistics" -> copy("Gelişimini takip et", "İstatistikler ekranında çalışmalarının güncel görünümünü gör.", "Aç", "chart.bar")
                "motivation.photo_analysis" -> copy("Yeni bir analizle başla", "Fotoğraf yükle, bulguları hızlıca gör.", "Başla", "camera")
                else -> null
            }
        }

        /** "2 saat önce" style; null when the server sent no usable time. */
        fun relative(value: String?, now: Instant): String? {
            val moment = value?.let { runCatching { Instant.parse(it) }.getOrNull() ?: runCatching {
                java.time.OffsetDateTime.parse(it).toInstant() }.getOrNull() } ?: return null
            val minutes = java.time.Duration.between(moment.coerceAtMost(now), now).toMinutes()
            return when {
                minutes < 1 -> "az önce"
                minutes < 60 -> "$minutes dakika önce"
                minutes < 24 * 60 -> "${minutes / 60} saat önce"
                minutes < 7 * 24 * 60 -> "${minutes / (24 * 60)} gün önce"
                else -> DateTimeFormatter.ofPattern("d MMMM", Locale.forLanguageTag("tr-TR"))
                    .format(moment.atZone(ZoneId.of("Europe/Istanbul")))
            }
        }
    }
}

sealed interface NovaForYouPhase {
    data object Loading : NovaForYouPhase
    data object Failed : NovaForYouPhase
    data class Ready(val feed: NovaForYouFeed) : NovaForYouPhase
}

private data class NovaForYouItem(val card: NovaForYouCard, val copy: NovaForYouCopy)

/**
 * "Senin İçin" home section (iOS `NovaForYouSection`): the feature suggestions rotate in the large area, with
 * one attention card and one progress card below ([NovaForYouLayout]). A card this build cannot word is
 * skipped and the next card of its kind takes its place; "Tümü" lists every card.
 */
@Composable
fun NovaForYouSection(phase: NovaForYouPhase, onOpen: (NovaForYouCard) -> Unit, onDismiss: (NovaForYouCard) -> Unit,
                      onRetry: () -> Unit, onShown: (List<NovaForYouCard>) -> Unit = {}, modifier: Modifier = Modifier,
                      /** The unfinished item this visit shows ([NovaForYouRotation]); null or gone means the first one. */
                      continueId: String? = null) {
    var showingAll by remember { mutableStateOf(false) }
    when (phase) {
        NovaForYouPhase.Loading -> Column(modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "Öneriler yükleniyor" }
            .testTag("nova.home.foryou.loading"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Header(false) {}
            Box(Modifier.fillMaxWidth().height(132.dp).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(20.dp)))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                repeat(2) { Box(Modifier.weight(1f).height(112.dp).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(18.dp))) }
            }
        }
        NovaForYouPhase.Failed -> Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Header(false) {}
            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(18.dp)).novaControlBackground(18.dp)
                .novaRowPress(onClick = onRetry).testTag("nova.home.foryou.retry").padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically) {
                NovaText("Öneriler yüklenemedi", Modifier.weight(1f), NovaTypeToken.meta, NovaColorToken.textSecondary.color())
                NovaText("Tekrar dene", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
            }
        }
        is NovaForYouPhase.Ready -> {
            val all = remember(phase.feed) {
                (phase.feed.cards + phase.feed.more).mapNotNull { card -> NovaForYouCopy.make(card)?.let { NovaForYouItem(card, it) } }
            }
            val layout = remember(all, continueId) { NovaForYouLayout.of(all, { it.card.kind }, { it.card.id }, continueId) }
            if (layout.size == 0) return
            val below = layout.boxes + listOfNotNull(layout.strip)
            val unfinished = all.filter { it.card.kind == "continue" }
            LaunchedEffect(below.map { it.card.id }) { onShown(below.map { it.card }) }
            Column(modifier.fillMaxWidth().testTag("nova.home.foryou"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Header(all.size > layout.size) { showingAll = true }
                if (layout.featured.isNotEmpty()) FeaturedArea(layout.featured, onOpen, onDismiss) { onShown(listOf(it.card)) }
                val boxes = layout.boxes
                if (novaFontScaleIsAccessibility()) boxes.forEach { SupportCard(it, unfinished, onOpen, onDismiss, Modifier.fillMaxWidth()) }
                else if (boxes.isNotEmpty()) Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    boxes.forEach { SupportCard(it, unfinished, onOpen, onDismiss, Modifier.weight(1f).fillMaxHeight()) }
                }
                layout.strip?.let { StripCard(it, onOpen, onDismiss) }
            }
            NovaPopup(showingAll, { showingAll = false }, identifier = "nova.home.foryou.all.popup") {
                NovaText("Senin İçin", style = NovaTypeToken.sheetTitle, modifier = Modifier.semantics { heading() })
                Spacer(Modifier.height(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    all.forEach { item ->
                        CardSurface(item, 18.dp, Modifier.fillMaxWidth().novaRowPress { showingAll = false; onOpen(item.card) }
                            .testTag("nova.home.foryou.all.${item.card.key}")) {
                            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Badge(item, 26.dp)
                                NovaText(item.copy.title, style = NovaTypeToken.bodyStrong)
                                NovaText(item.copy.detail, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
                                ActionRow(item)
                            }
                        }
                    }
                    if (phase.feed.hasMore) NovaText("Diğer kayıtlar ilgili modül listelerinde.", style = NovaTypeToken.metaQuiet,
                        color = NovaColorToken.textSecondary.color())
                }
            }
        }
    }
}

@Composable
private fun Header(showsAll: Boolean, onAll: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        NovaText("Senin İçin", Modifier.weight(1f).semantics { heading() }, NovaTypeToken.sectionTitle)
        if (showsAll) Box(Modifier.heightIn(min = 36.dp).novaRowPress(onClick = onAll).testTag("nova.home.foryou.all"),
            contentAlignment = Alignment.Center) {
            NovaText("Tümü", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
        }
    }
}

@Composable
private fun palette(tone: String): Pair<Color, Color> = when (tone) {
    "danger" -> NovaColorToken.statusDangerInk.color() to NovaColorToken.statusDangerBg.color()
    "warning", "feature" -> NovaColorToken.statusWarningInk.color() to NovaColorToken.statusWarningBg.color()
    "success" -> NovaColorToken.statusSuccessInk.color() to NovaColorToken.statusSuccessBg.color()
    else -> NovaColorToken.statusInfoInk.color() to NovaColorToken.statusInfoBg.color()
}

@Composable
private fun Badge(item: NovaForYouItem, size: Dp) {
    val (ink, soft) = colors(item)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Box(Modifier.size(size).background(soft, CircleShape), contentAlignment = Alignment.Center) {
            NovaIcon(item.copy.symbol, size * 0.46f, tint = ink)
        }
        NovaText(item.copy.label.uppercase(Locale.forLanguageTag("tr-TR")), style = NovaTypeToken.badge, color = ink, maxLines = 1)
    }
}

@Composable
private fun ActionRow(item: NovaForYouItem) {
    val ink = colors(item).first
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        NovaText(item.copy.action, style = NovaTypeToken.label, color = ink, maxLines = 1)
        NovaIcon("arrow.right", 11.dp, tint = ink)
    }
}

/** The featured card's action, text and arrow on a soft tinted capsule so it reads as a button (iOS `actionPill`). */
@Composable
private fun ActionPill(item: NovaForYouItem, modifier: Modifier = Modifier) {
    val ink = colors(item).first
    // A light base under the tint keeps the art's specks out of the label.
    Box(modifier.heightIn(min = 34.dp).clip(CircleShape).background(NovaColorToken.surface.color().copy(alpha = 0.75f))
        .background(ink.copy(alpha = 0.12f))
        .border(1.dp, ink.copy(alpha = 0.18f), CircleShape).padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center) {
        ActionRow(item)
    }
}

/**
 * The pastel artwork behind a kind's cards (iOS `artwork`). Light theme only: under the dark theme's light
 * text it would wash the copy out. The Keşfet art also stays off at the largest font sizes, where the text
 * needs the whole card.
 */
@Composable
private fun artwork(item: NovaForYouItem): Int? {
    if (LocalNovaDark.current) return null
    return when (item.card.kind) {
        "discover" -> if (LocalDensity.current.fontScale >= 1.5f) null else discoverArt(item).drawable
        "critical" -> R.drawable.nova_foryou_critical_background
        "continue" -> R.drawable.nova_foryou_continue_background
        else -> null
    }
}

/**
 * A Keşfet card's art, the colours along its top edge (at 0, 30, 50 and 100 % of the width), which fill the card
 * above the art, and the ink and soft fill its label, button and dot take on it (null: the tone's own).
 */
private class DiscoverArt(val drawable: Int, edge: List<Long>, accent: Pair<Long, Long>? = null) {
    val edge = edge.map(::opaque)
    val accent = accent?.let { opaque(it.first) to opaque(it.second) }
}

private fun opaque(rgb: Long) = Color(0xFF000000 or rgb)

/** Each feature's own art (iOS `discoverArt`); the others use the general Keşfet art. */
private val DISCOVER_ART = mapOf(
    "discover.risk_wizard" to DiscoverArt(R.drawable.nova_foryou_discover_risk_wizard, listOf(0xFCF7E8, 0xFBFBF9, 0xFBEECA, 0xFCE8B0)),
    "discover.photo_analysis" to DiscoverArt(R.drawable.nova_foryou_discover_photo_analysis, listOf(0xF6FAF1, 0xF7FCFA, 0xC3F1DD, 0xD1EDC0),
        0x1A6E4CL to 0xD8F3E6L),
    "discover.equipment" to DiscoverArt(R.drawable.nova_foryou_discover_equipment, listOf(0xEEFAFC, 0xEFFAFD, 0xCFF1FC, 0xBCE6F9),
        0x0B6E92L to 0xD6F0FAL),
    "discover.statistics" to DiscoverArt(R.drawable.nova_foryou_discover_statistics, listOf(0xF4F5FA, 0xF8FAFB, 0xD5E0FB, 0xD5DDFA),
        0x4B4BC0L to 0xE2E4FBL),
    "discover.training" to DiscoverArt(R.drawable.nova_foryou_discover_training, listOf(0xF7FCF2, 0xF7FDF4, 0xDFF2D5, 0xDBEED0),
        0x2E7A38L to 0xDDF1D6L),
    "discover.nonconformity" to DiscoverArt(R.drawable.nova_foryou_discover_nonconformity, listOf(0xFBF1ED, 0xFDF7F4, 0xFCD5CC, 0xFBC9BF),
        0xB02F24L to 0xFCDCD5L),
    "discover.emergency_wizard" to DiscoverArt(R.drawable.nova_foryou_discover_emergency_wizard, listOf(0xFCF7EC, 0xFDF9F2, 0xFDE5BE, 0xFBDFB0),
        0xA94A0CL to 0xFDE6CCL),
    "discover.checklist" to DiscoverArt(R.drawable.nova_foryou_discover_checklist, listOf(0xFCF4E1, 0xFDFAF3, 0xFCEFCA, 0xFDE8BA)),
)
/** How strongly the Keşfet art shows over the card surface (iOS `discoverArtOpacity`). */
private const val DISCOVER_ART_ALPHA = 0.8f

private val GENERAL_DISCOVER_ART = DiscoverArt(R.drawable.nova_foryou_discover_background, listOf(0xFDFCF9, 0xFCFBF9, 0xFDF3DE, 0xFEECC9))

private fun discoverArt(item: NovaForYouItem) = DISCOVER_ART[item.card.key] ?: GENERAL_DISCOVER_ART

/** The card's ink and soft fill (iOS `colors`): its art's accent while the art shows, otherwise the tone's. */
@Composable
private fun colors(item: NovaForYouItem): Pair<Color, Color> {
    val accent = if (item.card.kind == "discover" && artwork(item) != null) discoverArt(item).accent else null
    return accent ?: palette(item.card.tone)
}

/**
 * Drawn behind the content at the card's own size, so it never changes a card's height. The Keşfet art keeps
 * its illustration whole at the bottom right, over its own top-edge colours; the Dikkat and Devam et art fill
 * the box from the right, where their icon sits.
 */
@Composable
private fun BoxScope.ArtworkLayer(item: NovaForYouItem) {
    val art = artwork(item) ?: return
    val painter = painterResource(art)
    if (item.card.kind == "discover") {
        val edge = discoverArt(item).edge
        val ratio = painter.intrinsicSize.width / painter.intrinsicSize.height
        // Softened as one layer, so the copy stands out from the art.
        Box(Modifier.matchParentSize().graphicsLayer(alpha = DISCOVER_ART_ALPHA)) {
            Box(Modifier.matchParentSize().background(Brush.horizontalGradient(
                *listOf(0f, 0.3f, 0.5f, 1f).zip(edge).toTypedArray())))
            Image(painter, null, Modifier.matchParentSize()
                .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                .drawWithContent {
                    drawContent()
                    val artHeight = minOf(size.height, size.width / ratio)
                    val top = size.height - artHeight
                    drawRect(Brush.verticalGradient(0f to Color.Transparent, 1f to Color.Black,
                        startY = top, endY = top + artHeight * 0.12f), blendMode = BlendMode.DstIn)
                },
                alignment = Alignment.BottomEnd, contentScale = ContentScale.Fit)
        }
    } else {
        Image(painter, null, Modifier.matchParentSize(), alignment = Alignment.CenterEnd, contentScale = ContentScale.Crop)
    }
}

@Composable
private fun CardSurface(item: NovaForYouItem, radius: Dp, modifier: Modifier, content: @Composable () -> Unit) {
    val critical = item.card.kind == "critical"
    val shape = RoundedCornerShape(radius)
    Box(modifier.clip(shape).background(NovaColorToken.surface.color(), shape)
        .border(1.dp, if (critical) palette(item.card.tone).first.copy(alpha = 0.35f) else NovaColorToken.borderMuted.color(), shape)) {
        ArtworkLayer(item)
        content()
    }
}

@Composable
private fun DismissButton(item: NovaForYouItem, onDismiss: (NovaForYouCard) -> Unit, modifier: Modifier) {
    Box(modifier.size(44.dp).novaRowPress { onDismiss(item.card) }
        .semantics { contentDescription = "Öneriyi gizle" }.testTag("nova.home.foryou.dismiss.${item.card.key}"),
        contentAlignment = Alignment.Center) {
        Box(Modifier.size(28.dp).background(NovaColorToken.surfaceMuted.color(), CircleShape), contentAlignment = Alignment.Center) {
            NovaIcon("xmark", 11.dp, tint = NovaColorToken.textMuted.color())
        }
    }
}

/**
 * The feature suggestions, one at a time: they move on by themselves every few seconds and can be swiped
 * (iOS `featuredArea`). They stay put while dragged, for TalkBack and with animations removed. Every card is
 * laid out once, invisible, so the pager is as tall as the tallest and the page does not jump.
 */
@Composable
private fun FeaturedArea(items: List<NovaForYouItem>, onOpen: (NovaForYouCard) -> Unit, onDismiss: (NovaForYouCard) -> Unit,
                         onCurrent: (NovaForYouItem) -> Unit) {
    val pager = rememberPagerState { items.size }
    val context = LocalContext.current
    val talkBack = remember(context) {
        (context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)?.isTouchExplorationEnabled == true
    }
    val reduceMotion = rememberNovaReduceMotion()
    val dragged by pager.interactionSource.collectIsDraggedAsState()
    val settled = items.getOrNull(pager.settledPage) ?: items.first()
    LaunchedEffect(settled.card.id) { onCurrent(settled) }
    LaunchedEffect(pager.settledPage, items.size, dragged, talkBack, reduceMotion) {
        if (items.size < 2 || dragged || talkBack || reduceMotion) return@LaunchedEffect
        delay(5_000)
        pager.animateScrollToPage((pager.settledPage + 1) % items.size)
    }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.fillMaxWidth()) {
            Box(Modifier.fillMaxWidth().alpha(0f).clearAndSetSemantics {}) { items.forEach { MainCard(it, null, onDismiss) } }
            HorizontalPager(pager, Modifier.matchParentSize(), pageSpacing = 12.dp, key = { items[it].card.id }) { page ->
                MainCard(items[page], onOpen, onDismiss)
            }
        }
        if (items.size > 1) Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items.forEachIndexed { index, item ->
                val on = index == pager.currentPage
                val width by animateDpAsState(if (on) 18.dp else 6.dp, label = "foryou.dot")
                Box(Modifier.height(6.dp).width(width)
                    .background(if (on) colors(item).first else NovaColorToken.borderMuted.color(), CircleShape))
            }
        }
    }
}

/** A null [onOpen] draws the card only to take its size. */
@Composable
private fun MainCard(item: NovaForYouItem, onOpen: ((NovaForYouCard) -> Unit)?, onDismiss: (NovaForYouCard) -> Unit) {
    Box(Modifier.fillMaxWidth()) {
        CardSurface(item, 20.dp, Modifier.fillMaxWidth()
            .then(if (onOpen == null) Modifier else Modifier.novaRowPress { onOpen(item.card) })
            .testTag("nova.home.foryou.featured.${item.card.key}").semantics(mergeDescendants = true) {}) {
            // The Keşfet art's illustration takes the right side.
            Column(Modifier.padding(16.dp).padding(end = when {
                item.card.kind == "discover" && artwork(item) != null -> 124.dp
                item.card.dismissible -> 28.dp
                else -> 0.dp
            }),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Badge(item, 34.dp)
                NovaText(item.copy.title, style = NovaTypeToken.dialogTitle, maxLines = 3)
                NovaText(item.copy.detail, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color(), maxLines = 3)
                ActionPill(item, Modifier.padding(top = 2.dp))
            }
        }
        if (onOpen != null && item.card.dismissible) DismissButton(item, onDismiss, Modifier.align(Alignment.TopEnd).padding(4.dp))
    }
}

/**
 * A compact box (iOS `supportCard`): the kind, the line in regular weight and a coloured arrow. The unfinished
 * item shows its place among all unfinished items ("2/5"); the others take turns on later visits and are all in "Tümü".
 */
@Composable
private fun SupportCard(item: NovaForYouItem, unfinished: List<NovaForYouItem>, onOpen: (NovaForYouCard) -> Unit,
                        onDismiss: (NovaForYouCard) -> Unit, modifier: Modifier) {
    val index = unfinished.indexOfFirst { it.card.id == item.card.id }
    val place = if (unfinished.size > 1 && index >= 0) "${index + 1}/${unfinished.size}" else null
    Box(modifier) {
        CardSurface(item, 18.dp, Modifier.fillMaxSize().novaRowPress { onOpen(item.card) }
            .testTag("nova.home.foryou.card.${item.card.key}").semantics(mergeDescendants = true) { contentDescription = item.copy.detail }) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.padding(end = if (item.card.dismissible) 30.dp else 0.dp)) { Badge(item, 24.dp) }
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    NovaText(item.copy.title, Modifier.weight(1f), NovaTypeToken.metaQuiet, NovaColorToken.textSecondary.color(), maxLines = 3)
                    if (place != null) NovaText(place, Modifier.testTag("nova.home.foryou.place").semantics { hideFromAccessibility() },
                        NovaTypeToken.micro, NovaColorToken.textMuted.color(), maxLines = 1)
                    NovaIcon("arrow.right", 13.dp, tint = palette(item.card.tone).first)
                }
            }
        }
        if (item.card.dismissible) DismissButton(item, onDismiss, Modifier.align(Alignment.TopEnd))
    }
}

/** Progress as a slim full-width strip under the two boxes (iOS `stripCard`). */
@Composable
private fun StripCard(item: NovaForYouItem, onOpen: (NovaForYouCard) -> Unit, onDismiss: (NovaForYouCard) -> Unit) {
    val (ink, soft) = palette(item.card.tone)
    Box(Modifier.fillMaxWidth()) {
        CardSurface(item, 18.dp, Modifier.fillMaxWidth().novaRowPress { onOpen(item.card) }
            .testTag("nova.home.foryou.strip.${item.card.key}").semantics(mergeDescendants = true) { contentDescription = item.copy.detail }) {
            Row(Modifier.padding(12.dp).padding(end = if (item.card.dismissible) 32.dp else 0.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(34.dp).background(soft, CircleShape), contentAlignment = Alignment.Center) {
                    NovaIcon(item.copy.symbol, 15.dp, tint = ink)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    NovaText(item.copy.title, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color(), maxLines = 2)
                    ActionRow(item)
                }
            }
        }
        if (item.card.dismissible) DismissButton(item, onDismiss, Modifier.align(Alignment.CenterEnd))
    }
}

/**
 * Loads the cards for the signed-in session and turns what the user does with them into queued events
 * (iOS `NovaForYouHost` + `NovaForYouModel`). Reloads on resume, on record changes and when [refreshKey]
 * changes; a failed refresh keeps the cards already on screen.
 */
@Composable
fun NovaForYouHost(load: suspend () -> NovaForYouFeed, pending: () -> List<NovaForYouEvent>, record: (NovaForYouEvent) -> Unit,
                   changes: Flow<Unit>, refreshKey: Any?, onOpen: (NovaForYouCard) -> Unit,
                   onFeed: (NovaForYouFeed?) -> Unit = {}, modifier: Modifier = Modifier,
                   /** The last answer for this user and workspace: returning home draws at once while the fresh one loads. */
                   cached: NovaForYouFeed? = null,
                   /** The unfinished item's turn; one host is one visit, and coming back to the app starts another. */
                   rotation: NovaForYouRotation? = null) {
    /** Cards hidden by an event not yet confirmed stay hidden; the last decision per card wins. */
    fun visible(value: NovaForYouFeed): NovaForYouFeed {
        val hidden = mutableMapOf<String, Boolean>()
        pending().sortedBy { it.occurredAt }.forEach { event ->
            event.cards.forEach { card ->
                when {
                    event.action == "dismiss" -> hidden[card] = true
                    event.action == "restore" -> hidden[card] = false
                    event.action == "act" && card.startsWith("discover.") -> hidden[card] = true
                }
            }
        }
        return value.removing(hidden.filterValues { it }.keys)
    }
    var feed by remember { mutableStateOf(cached?.let(::visible)) }
    var failed by remember { mutableStateOf(false) }
    var revision by remember { mutableIntStateOf(0) }
    val reported = remember { mutableSetOf<String>() }

    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    var wasResumed by remember { mutableStateOf(true) }
    var visit by remember { mutableIntStateOf(0) }
    LaunchedEffect(lifecycle) {
        val resumed = lifecycle.isAtLeast(Lifecycle.State.RESUMED)
        if (resumed && !wasResumed) { revision++; rotation?.newVisit(); visit++ }
        wasResumed = resumed
    }
    LaunchedEffect(changes) { changes.collect { revision++ } }
    LaunchedEffect(refreshKey, revision) {
        try {
            val value = visible(load())
            feed = value; failed = false; onFeed(value)
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (feed == null) failed = true
        }
    }
    fun emit(event: NovaForYouEvent) {
        record(event)
        feed?.let { current -> visible(current).also { feed = it; onFeed(it) } }
    }
    val phase = feed?.let { NovaForYouPhase.Ready(it) } ?: if (failed) NovaForYouPhase.Failed else NovaForYouPhase.Loading
    val continueId = remember(feed, visit) {
        feed?.let { value ->
            rotation?.pick((value.cards + value.more).filter { it.kind == "continue" && NovaForYouCopy.make(it) != null }.map { it.id })
        }
    }
    NovaForYouSection(phase,
        onOpen = { card -> emit(NovaForYouEvent.card("act", listOf(card.id))); onOpen(card) },
        onDismiss = { card -> emit(NovaForYouEvent.card("dismiss", listOf(card.id))) },
        onRetry = { failed = false; revision++ },
        onShown = { cards ->
            val day = java.time.LocalDate.now(ZoneId.of("Europe/Istanbul")).toString()
            val fresh = cards.filter { it.kind in setOf("discover", "performance", "motivation") && reported.add("$day|${it.id}") }
            // The server takes at most five cards per event.
            fresh.map { it.id }.chunked(5).forEach { record(NovaForYouEvent.card("shown", it)) }
        },
        modifier = modifier, continueId = continueId)
}
