package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/** The activity log's calls bound to one identity and workspace; the design preview supplies its own. */
interface NovaActivityClient {
    suspend fun page(after: Long?, from: String?, action: String?, company: String?): NovaActivityPage
    suspend fun detail(event: Long): NovaActivityDetail
}

class NovaServiceActivityClient(private val service: NovaActivityService, private val identity: IsgWorkspaceIdentity,
                                private val workspace: String?, private val member: String? = null) : NovaActivityClient {
    override suspend fun page(after: Long?, from: String?, action: String?, company: String?) =
        service.page(identity, workspace, member, after, from, action, company)
    override suspend fun detail(event: Long) = service.detail(identity, event, workspace)
}

private fun activityDate(value: String): String = runCatching {
    DateTimeFormatter.ofPattern("d MMM yyyy HH:mm", Locale.forLanguageTag("tr-TR")).format(OffsetDateTime.parse(value).atZoneSameInstant(ZoneId.systemDefault()))
}.getOrDefault("—")

/**
 * Aktivitem (iOS `ExpertActivityDestination`): active time and the record log. The same page serves a
 * manager inspecting one member ([member] true). [onOpenRecord] opens a record's company or module.
 */
@Composable
fun NovaActivityScreen(client: NovaActivityClient, onClose: () -> Unit, member: Boolean = false,
                       onOpenRecord: ((NovaActivityDetail, companyOnly: Boolean) -> Unit)? = null) {
    val coroutines = rememberCoroutineScope()
    var summary by remember { mutableStateOf<NovaUsageSummary?>(null) }
    var items by remember { mutableStateOf<List<NovaActivityItem>>(emptyList()) }
    var cursor by remember { mutableStateOf<Long?>(null) }
    var days by remember { mutableIntStateOf(30) }
    var action by remember { mutableStateOf<String?>(null) }
    var company by remember { mutableStateOf<String?>(null) }
    var actions by remember { mutableStateOf<List<String>>(emptyList()) }
    var companies by remember { mutableStateOf<List<NovaActivityPage.Company>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<NovaActivityDetail?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var epoch by remember { mutableIntStateOf(0) }
    suspend fun load(reset: Boolean) {
        if (!reset && loading) return
        val mine = ++epoch
        loading = true; error = null
        try {
            val from = if (days == 0) null else Instant.now().minus(days.toLong(), ChronoUnit.DAYS).truncatedTo(ChronoUnit.SECONDS).toString()
            val result = client.page(if (reset) null else cursor, from, action, company)
            if (mine != epoch) return
            summary = result.summary; actions = result.actions.orEmpty(); companies = result.companies.orEmpty()
            items = if (reset) result.items else items + result.items
            cursor = result.nextCursor
        } catch (_: Exception) { if (mine == epoch) error = "Aktivite bilgileri yüklenemedi. Lütfen yeniden deneyin." }
        if (mine == epoch) loading = false
    }
    LaunchedEffect(days, action, company) { load(true) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("nova.activity.screen"), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaPageHeading(if (member) "Uzman aktivitesi" else "Aktivitem", onBack = onClose)
        summary?.let { value ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val metrics = buildList {
                    add("Bugün" to value.todaySeconds); add("Son 7 gün" to value.weekSeconds); add("Son 30 gün" to value.monthSeconds)
                    add((if (member) "Üyelik döneminde" else "Toplam aktif süre") to value.totalSeconds); add("Son oturum" to value.sessionSeconds)
                    if (member) add("Bu OSGB'de" to value.workspaceSeconds)
                }
                metrics.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        pair.forEach { (title, seconds) ->
                            NovaCard(Modifier.weight(1f), padding = 12) {
                                NovaText(NovaUsageSummary.duration(seconds), style = NovaTypeToken.sectionTitle)
                                NovaText(title, style = NovaTypeToken.metaQuiet)
                            }
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                NovaText("Giriş sayısı: ${value.loginCount}", style = NovaTypeToken.metaQuiet)
                NovaText("Son giriş: ${value.lastLoginAt?.let(::activityDate) ?: "Henüz yok"}", style = NovaTypeToken.metaQuiet)
                NovaText("Son aktiflik: ${value.lastActiveAt?.let(::activityDate) ?: "Henüz yok"}", style = NovaTypeToken.metaQuiet)
            }
        }
        val ranges = listOf(7, 30, 0)
        NovaSegmentedControl(listOf("7 gün", "30 gün", "Tümü"), ranges.indexOf(days)) { days = ranges[it] }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("İşlem türü", action?.let { NovaActivityWords.title(it) } ?: "Tüm işlemler", "nova.activity.action", Modifier.weight(1f),
                open = chooser == "action") { chooser = if (chooser == "action") null else "action" }
            NovaChooserButton("Firma", companies.firstOrNull { it.id == company }?.name ?: "Tüm firmalar", "nova.activity.company", Modifier.weight(1f),
                open = chooser == "company") { chooser = if (chooser == "company") null else "company" }
        }
        if (chooser == "action") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm işlemler")) +
            actions.map { NovaChooserOption(it, NovaActivityWords.title(it)) }, action, "nova.activity.action.panel") { action = it; chooser = null }
        if (chooser == "company") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm firmalar")) +
            companies.map { NovaChooserOption(it.id, it.name) }, company, "nova.activity.company.panel") { company = it; chooser = null }
        error?.let {
            NovaHelpHint(it)
            NovaButton("Yeniden dene", { coroutines.launch { load(true) } }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
        }
        if (items.isEmpty() && !loading && error == null)
            NovaHelpHint("Bu tarih aralığında kayıtlı işlem yok. Kullanım süreleri özellik etkinleştirildikten sonra birikir.")
        items.forEach { item ->
            NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress {
                coroutines.launch {
                    try { detail = client.detail(item.id) } catch (_: Exception) { error = "İşlem detayı alınamadı. Erişiminizi ve bağlantınızı kontrol edin." }
                }
            }.testTag("nova.activity.item.${item.id}"), padding = 14) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        NovaText(item.title, style = NovaTypeToken.bodyStrong)
                        item.companyName?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                        NovaText(activityDate(item.createdAt), style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
                    }
                    NovaIcon("chevron.right", 12.dp)
                }
            }
        }
        if (loading) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 22.dp) }
        if (cursor != null) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface, enabled = !loading,
            symbol = "chevron.down")
    }
    val open = detail
    NovaPopup(open != null, { detail = null }, identifier = "nova.activity.detail") {
        if (open != null) Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            NovaPopupHeading("İşlem detayı", symbol = "clock.arrow.circlepath")
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                NovaText("İşlem", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                NovaText(items.firstOrNull { it.id == open.id }?.title ?: "İşlem kaydı", style = NovaTypeToken.bodyStrong)
                NovaText(activityDate(open.createdAt), style = NovaTypeToken.metaQuiet)
            }
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaText("Değişiklikler", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                    if (open.changes.isEmpty()) NovaText("Bu işlem için gösterilebilir alan değişikliği yok.", style = NovaTypeToken.meta)
                    open.changes.forEach { change ->
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            NovaText(NovaActivityWords.field(change.field), style = NovaTypeToken.bodyStrong)
                            NovaText("${NovaActivityWords.value(change.before)} → ${NovaActivityWords.value(change.after)}", style = NovaTypeToken.meta)
                        }
                    }
                }
            }
            open.stages?.takeIf { it.isNotEmpty() }?.let { stages ->
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        NovaText("İşlem aşamaları", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                        stages.forEach { stage ->
                            NovaText(NovaActivityWords.title(open.entityType + "." + stage.status), style = NovaTypeToken.body)
                            NovaText(activityDate(stage.at), style = NovaTypeToken.micro, color = NovaColorToken.textSecondary.color())
                        }
                    }
                }
            }
            if (open.linkCompanyId != null && onOpenRecord != null) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaText("İlgili kayıt", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                NovaPopupOption("Firmayı aç", "building.2") { detail = null; onOpenRecord(open, true) }
                if (open.entityType != "company" && open.entityId != null)
                    NovaPopupOption("İlgili modüldeki kaydı aç", "arrow.up.right.square") { detail = null; onOpenRecord(open, false) }
            }
            NovaText("Kişisel not içeriği, iletişim bilgileri, dosyalar ve AI içerikleri bu günlüğe dahil edilmez.", style = NovaTypeToken.micro,
                color = NovaColorToken.textSecondary.color())
        }
    }
}
