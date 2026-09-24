package com.riskdetectedan.feature.nova

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.riskdetectedan.core.data.nova.NovaForYouCard
import com.riskdetectedan.core.data.nova.NovaForYouEvent
import com.riskdetectedan.core.data.nova.NovaForYouFeed
import com.riskdetectedan.core.data.nova.NovaFollowupPage
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

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
 * "Senin İçin" home section (iOS `NovaForYouSection`): one main card and two support cards, in the order the
 * server ranked them. A card this build cannot word is skipped and the next one takes its place, with at most
 * one suggestion; "Tümü" lists every card.
 */
@Composable
fun NovaForYouSection(phase: NovaForYouPhase, onOpen: (NovaForYouCard) -> Unit, onDismiss: (NovaForYouCard) -> Unit,
                      onRetry: () -> Unit, onShown: (List<NovaForYouCard>) -> Unit = {}, modifier: Modifier = Modifier) {
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
            val shown = remember(all) {
                val picked = mutableListOf<NovaForYouItem>()
                for (item in all) {
                    if (picked.size == 3) break
                    if (item.card.kind == "discover" && picked.any { it.card.kind == "discover" }) continue
                    picked += item
                }
                picked.toList()
            }
            if (shown.isEmpty()) return
            LaunchedEffect(shown.map { it.card.id }) { onShown(shown.map { it.card }) }
            Column(modifier.fillMaxWidth().testTag("nova.home.foryou"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Header(all.size > shown.size) { showingAll = true }
                MainCard(shown[0], onOpen, onDismiss)
                val support = shown.drop(1)
                if (novaFontScaleIsAccessibility()) support.forEach { SupportCard(it, onOpen, onDismiss, Modifier.fillMaxWidth()) }
                else if (support.isNotEmpty()) Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    support.forEach { SupportCard(it, onOpen, onDismiss, Modifier.weight(1f).fillMaxHeight()) }
                }
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
    val (ink, soft) = palette(item.card.tone)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Box(Modifier.size(size).background(soft, CircleShape), contentAlignment = Alignment.Center) {
            NovaIcon(item.copy.symbol, size * 0.46f, tint = ink)
        }
        NovaText(item.copy.label.uppercase(Locale.forLanguageTag("tr-TR")), style = NovaTypeToken.badge, color = ink, maxLines = 1)
    }
}

@Composable
private fun ActionRow(item: NovaForYouItem) {
    val ink = palette(item.card.tone).first
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        NovaText(item.copy.action, style = NovaTypeToken.label, color = ink, maxLines = 1)
        NovaIcon("arrow.right", 11.dp, tint = ink)
    }
}

@Composable
private fun CardSurface(item: NovaForYouItem, radius: Dp, modifier: Modifier, content: @Composable () -> Unit) {
    val critical = item.card.kind == "critical"
    val shape = RoundedCornerShape(radius)
    Box(modifier.clip(shape).background(NovaColorToken.surface.color(), shape)
        .border(1.dp, if (critical) palette(item.card.tone).first.copy(alpha = 0.35f) else NovaColorToken.borderMuted.color(), shape)) {
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

@Composable
private fun MainCard(item: NovaForYouItem, onOpen: (NovaForYouCard) -> Unit, onDismiss: (NovaForYouCard) -> Unit) {
    Box(Modifier.fillMaxWidth()) {
        CardSurface(item, 20.dp, Modifier.fillMaxWidth().novaRowPress { onOpen(item.card) }.testTag("nova.home.foryou.main")
            .semantics(mergeDescendants = true) {}) {
            Column(Modifier.padding(16.dp).padding(end = if (item.card.dismissible) 28.dp else 0.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Badge(item, 34.dp)
                NovaText(item.copy.title, style = NovaTypeToken.dialogTitle, maxLines = 3)
                NovaText(item.copy.detail, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color(), maxLines = 3)
                ActionRow(item)
            }
        }
        if (item.card.dismissible) DismissButton(item, onDismiss, Modifier.align(Alignment.TopEnd).padding(4.dp))
    }
}

@Composable
private fun SupportCard(item: NovaForYouItem, onOpen: (NovaForYouCard) -> Unit, onDismiss: (NovaForYouCard) -> Unit, modifier: Modifier) {
    Box(modifier) {
        CardSurface(item, 18.dp, Modifier.fillMaxSize().novaRowPress { onOpen(item.card) }
            .testTag("nova.home.foryou.card.${item.card.key}").semantics(mergeDescendants = true) { contentDescription = item.copy.detail }) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Box(Modifier.padding(end = if (item.card.dismissible) 30.dp else 0.dp)) { Badge(item, 26.dp) }
                NovaText(item.copy.title, style = NovaTypeToken.bodyStrong, maxLines = 3)
                Spacer(Modifier.weight(1f))
                ActionRow(item)
            }
        }
        if (item.card.dismissible) DismissButton(item, onDismiss, Modifier.align(Alignment.TopEnd))
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
                   cached: NovaForYouFeed? = null) {
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
    LaunchedEffect(lifecycle) {
        val resumed = lifecycle.isAtLeast(Lifecycle.State.RESUMED)
        if (resumed && !wasResumed) revision++
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
    NovaForYouSection(phase,
        onOpen = { card -> emit(NovaForYouEvent.card("act", listOf(card.id))); onOpen(card) },
        onDismiss = { card -> emit(NovaForYouEvent.card("dismiss", listOf(card.id))) },
        onRetry = { failed = false; revision++ },
        onShown = { cards ->
            val day = java.time.LocalDate.now(ZoneId.of("Europe/Istanbul")).toString()
            val fresh = cards.filter { it.kind in setOf("discover", "performance", "motivation") && reported.add("$day|${it.id}") }
            if (fresh.isNotEmpty()) record(NovaForYouEvent.card("shown", fresh.map { it.id }.take(5)))
        },
        modifier = modifier)
}
