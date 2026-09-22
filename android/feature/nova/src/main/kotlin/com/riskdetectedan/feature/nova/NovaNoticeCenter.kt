package com.riskdetectedan.feature.nova

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** The screen never sees the SDK; the root hands it these calls. */
class NovaNoticeClient(
    val feed: suspend (NovaNoticeScope) -> NovaNoticeFeed,
    val read: suspend (String) -> Unit,
    val readAll: suspend () -> Unit,
    val dismiss: suspend (String) -> Unit,
    val dismissAll: suspend () -> Unit,
    val restore: suspend (String) -> Unit,
)

internal val NovaNoticeSeverity.status get() = if (this == NovaNoticeSeverity.overdue) NovaStatus.Danger else NovaStatus.Warning
internal val NovaNoticeSeverity.tone get() = if (this == NovaNoticeSeverity.overdue) NovaColorToken.statusDangerInk else NovaColorToken.statusWarningInk

internal fun noticeFailureMessage(error: Throwable): String = when ((error as? NovaExpertFailure)?.code) {
    "ACCESS_DENIED", "AUTH_REQUIRED" -> "Bu bildirimlere erişim yok."
    "FEATURE_UNAVAILABLE" -> "Bildirimler henüz açık değil."
    "VALIDATION_ERROR" -> "İstek geçersiz."
    "NOT_FOUND" -> "Bu bildirim artık geçerli değil. Liste yenilendi."
    else -> "Bildirimler alınamadı. Bağlantıyı kontrol edip tekrar deneyin."
}

/** One notice as a card: the card opens the record, the controls change only this list. */
@Composable
fun NovaNoticeCard(entry: NovaNoticeEntry, onOpen: () -> Unit, onRead: () -> Unit, onDismiss: () -> Unit,
                   onRestore: () -> Unit) {
    NovaCard(Modifier.fillMaxWidth().alpha(if (entry.dismissed) 0.55f else 1f), padding = 13) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.weight(1f).novaRowPress(onClick = onOpen).testTag("nova.notice.center.row.${entry.key}"),
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) {
                    NovaIcon(entry.kind.symbol, 20.dp, tint = entry.severity.tone.color())
                    if (entry.unread) Box(Modifier.align(Alignment.TopEnd).size(5.dp)
                        .background(NovaColorToken.statusDangerDot.color(), CircleShape))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        NovaText(entry.title, Modifier.weight(1f), NovaTypeToken.cardTitle)
                        NovaStatusPill(entry.kind.title, entry.severity.status)
                    }
                    NovaText(NovaNoticeWords.explain(entry), style = NovaTypeToken.meta, color = entry.severity.tone.color())
                    entry.companyName?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color()) }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (entry.dismissed) NoticeCardAction("arrow.uturn.backward", "Geri al", "nova.notice.center.restore.${entry.key}", false, onRestore)
                else {
                    NoticeCardAction(if (entry.unread) "envelope.open" else "envelope", "Okundu işaretle",
                        "nova.notice.center.read.${entry.key}", !entry.unread, onRead)
                    NoticeCardAction("trash", "Bildirimi sil", "nova.notice.center.dismiss.${entry.key}", false, onDismiss)
                }
            }
        }
    }
}

@Composable
private fun NoticeCardAction(symbol: String, label: String, tag: String, disabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(40.dp).novaRowPress(!disabled, onClick = onClick).alpha(if (disabled) 0.4f else 1f)
        .semantics { contentDescription = label }.testTag(tag), contentAlignment = Alignment.Center) {
        NovaIcon(symbol, 14.dp, tint = NovaColorToken.textMuted.color())
    }
}

/** Bildirim Merkezi: everything the bell holds, with the two things the bell has no room to say. */
@Composable
fun NovaNoticeCenterScreen(client: NovaNoticeClient, onOpen: (String) -> Unit, onBack: () -> Unit) {
    var feed by remember { mutableStateOf(NovaNoticeFeed.empty) }
    var scope by remember { mutableStateOf(NovaNoticeScope.active) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    val coroutines = rememberCoroutineScope()
    suspend fun load() {
        loading = true; failure = null
        try { feed = client.feed(scope) } catch (error: Exception) { failure = noticeFailureMessage(error) }
        loading = false
    }
    /** Every write refreshes from the server; the counts are the server's to state. */
    fun run(reload: Boolean = true, work: suspend () -> Unit) {
        coroutines.launch {
            try { work(); if (reload) load() } catch (error: Exception) {
                failure = noticeFailureMessage(error)
                if ((error as? NovaExpertFailure)?.code == "NOT_FOUND") load()
            }
        }
    }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(top = 12.dp, bottom = 24.dp + novaTabBarInset), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaButton("Geri", onBack, variant = NovaButtonVariant.Surface, symbol = "chevron.left", compact = true)
                Spacer(Modifier.weight(1f))
                NovaButton("Tümünü oku", { run { client.readAll() } }, variant = NovaButtonVariant.Surface,
                    symbol = "envelope.open", compact = true, enabled = feed.unread > 0)
                NovaButton("Listeyi temizle", { run { client.dismissAll() } }, variant = NovaButtonVariant.Muted,
                    symbol = "trash", compact = true, enabled = feed.total > 0)
            }
            NovaText(NovaDestination.notifications.title, style = NovaTypeToken.screenTitle)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaListStat("Geçmiş", "exclamationmark.triangle", feed.overdue, Modifier.weight(1f))
            NovaListStat("Okunmamış", "envelope.badge", feed.unread, Modifier.weight(1f))
            NovaListStat("Açık", "bell", feed.total, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            NovaNoticeScope.entries.forEach { value ->
                val on = scope == value
                Box(Modifier.heightIn(min = 36.dp).border(1.dp, NovaColorToken.hairline.color(), RoundedCornerShape(10.dp))
                    .novaRowPress { scope = value; coroutines.launch { load() } }
                    .testTag("nova.notice.center.scope.${value.name}").padding(horizontal = 11.dp, vertical = 7.dp),
                    contentAlignment = Alignment.Center) {
                    NovaSizedText(value.title, 11f, if (on) FontWeight.Bold else FontWeight.Medium,
                        if (on) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color())
                }
            }
        }
        when {
            loading && feed.rows.isEmpty() -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                NovaText(failure!!, color = NovaColorToken.statusDangerInk.color())
            }
            feed.rows.isEmpty() -> NovaEmptyState("Bekleyen bildirim yok",
                "Kayıtlarınızın tarihleri yaklaştığında bildirimler burada görünür.")
            else -> NovaListEntrance(feed.rows.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    feed.rows.forEachIndexed { index, entry ->
                        Box(Modifier.novaRowEntrance(index)) {
                            NovaNoticeCard(entry,
                                onOpen = { run(reload = false) { client.read(entry.key) }; onOpen(entry.destination) },
                                onRead = { run { client.read(entry.key) } },
                                onDismiss = { run { client.dismiss(entry.key) } },
                                onRestore = { run { client.restore(entry.key) } })
                        }
                    }
                    if (feed.hasMore) NovaText("Daha fazlası var; yaklaşan tarihler önce gösterilir.",
                        style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaHelpHint(NovaNoticeWords.noPushNote)
            NovaText(NovaNoticeWords.dismissNote, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
    }
}
