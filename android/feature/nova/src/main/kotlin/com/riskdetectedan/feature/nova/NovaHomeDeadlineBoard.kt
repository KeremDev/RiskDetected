package com.riskdetectedan.feature.nova

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.riskdetectedan.core.data.nova.NovaFollowupPage
import com.riskdetectedan.core.data.nova.NovaEquipmentWords
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

private enum class DeadlineBucket(val title: String, val symbol: String, val status: String, val empty: String,
                                  val background: NovaColorToken, val ink: NovaColorToken, val tag: String) {
    overdue("Süresi Geçenler", "exclamationmark.circle", "expired", "Süresi geçen iş yok",
        NovaColorToken.statusDangerBg, NovaColorToken.statusDangerInk, "overdue"),
    upcoming("Yaklaşan", "calendar.badge.clock", "soon", "Yaklaşan iş yok",
        NovaColorToken.statusInfoBg, NovaColorToken.statusInfoInk, "upcoming"),
}

private class DeadlineColumn {
    var rows by mutableStateOf<List<NovaFollowupPage.Row>>(emptyList())
    var count by mutableIntStateOf(0)
    var hasMore by mutableStateOf(false)
    var expanded by mutableStateOf(false)
}

/**
 * Record-level deadlines on the home page (iOS `NovaHomeDeadlineBoard`). The source is the same scoped
 * timeline Evrak Takibi reads; counts are never turned into fake cards. [load] asks for one status
 * ("expired" or "soon") from an offset; [onOpen] shows the record in place of the home page.
 */
@Composable
fun NovaHomeDeadlineBoard(load: suspend (status: String, offset: Int) -> NovaFollowupPage, changes: Flow<Unit>,
                          scopeKey: Any?, onPendingActionCount: (Int?) -> Unit = {}, onOpen: (NovaFollowupPage.Row) -> Unit) {
    val columns = remember { DeadlineBucket.entries.associateWith { DeadlineColumn() } }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var loadingMore by remember { mutableStateOf<DeadlineBucket?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    val coroutines = rememberCoroutineScope()

    // iOS refreshes when the scene turns active again and when a record changes.
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    var wasResumed by remember { mutableStateOf(true) }
    LaunchedEffect(lifecycle) {
        val resumed = lifecycle.isAtLeast(Lifecycle.State.RESUMED)
        if (resumed && !wasResumed) revision++
        wasResumed = resumed
    }
    LaunchedEffect(changes) { changes.collect { revision++ } }

    LaunchedEffect(scopeKey, revision) {
        loading = true; failed = false
        try {
            coroutineScope {
                val late = async { load(DeadlineBucket.overdue.status, 0) }
                val soon = async { load(DeadlineBucket.upcoming.status, 0) }
                val (latePage, soonPage) = late.await() to soon.await()
                columns.getValue(DeadlineBucket.overdue).apply { rows = latePage.rows; count = latePage.expired; hasMore = latePage.hasMore }
                columns.getValue(DeadlineBucket.upcoming).apply { rows = soonPage.rows; count = soonPage.soon; hasMore = soonPage.hasMore }
                onPendingActionCount(latePage.expired + soonPage.soon)
            }
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (_: Exception) {
            failed = true
            onPendingActionCount(null)
        }
        loading = false
    }

    fun loadMore(bucket: DeadlineBucket) {
        if (loadingMore != null) return
        val column = columns.getValue(bucket)
        loadingMore = bucket
        coroutines.launch {
            // Keep the already visible records on failure; the next tap can retry.
            runCatching { load(bucket.status, column.rows.size) }.getOrNull()?.let { page ->
                column.rows = column.rows + page.rows; column.hasMore = page.hasMore
            }
            loadingMore = null
        }
    }

    val content: @Composable (DeadlineBucket, Modifier) -> Unit = { bucket, modifier ->
        DeadlineColumnView(bucket, columns.getValue(bucket), loading, failed, loadingMore == bucket, modifier,
            onRetry = { revision++ }, onMore = { loadMore(bucket) }, onOpen = onOpen)
    }
    Box(Modifier.testTag("nova.home.deadlines")) {
        if (novaFontScaleIsAccessibility()) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                DeadlineBucket.entries.forEach { content(it, Modifier.fillMaxWidth()) }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                DeadlineBucket.entries.forEach { content(it, Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun DeadlineColumnView(bucket: DeadlineBucket, column: DeadlineColumn, loading: Boolean, failed: Boolean, loadingMore: Boolean,
                               modifier: Modifier, onRetry: () -> Unit, onMore: () -> Unit, onOpen: (NovaFollowupPage.Row) -> Unit) {
    val ink = bucket.ink.color()
    val muted = NovaColorToken.textSecondary.color()
    val visible = if (column.expanded) column.rows else column.rows.take(3)
    Column(modifier.background(bucket.background.color(), RoundedCornerShape(20.dp)).padding(10.dp)
        .animateContentSize(tween(200)).testTag("nova.home.deadlines.${bucket.tag}"),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.heightIn(min = 30.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            NovaIcon(bucket.symbol, 13.dp, tint = ink)
            NovaText(bucket.title, Modifier.weight(1f), NovaTypeToken.bodyStrong, ink, maxLines = 1)
            Box(Modifier.defaultMinSize(26.dp, 26.dp).background(ink.copy(alpha = 0.10f), CircleShape), contentAlignment = Alignment.Center) {
                NovaText(if (loading) "·" else column.count.toString(), style = NovaTypeToken.meta, color = ink)
            }
        }
        when {
            loading -> Box(Modifier.fillMaxWidth().heightIn(min = 66.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(22.dp), color = ink, strokeWidth = 2.dp)
            }
            failed -> {
                NovaText("Kayıtlar yüklenemedi", Modifier.fillMaxWidth().heightIn(min = 66.dp), NovaTypeToken.meta, muted)
                Box(Modifier.heightIn(min = 36.dp).novaRowPress(onClick = onRetry), contentAlignment = Alignment.CenterStart) {
                    NovaText("Tekrar dene", style = NovaTypeToken.meta, color = ink)
                }
            }
            column.rows.isEmpty() -> NovaText(bucket.empty, Modifier.fillMaxWidth().heightIn(min = 66.dp), NovaTypeToken.meta, muted)
            else -> {
                visible.forEach { row -> DeadlineCard(row, ink) { onOpen(row) } }
                if (column.rows.size > 3 || column.hasMore) {
                    if (column.expanded && column.hasMore) {
                        Box(Modifier.fillMaxWidth().heightIn(min = 36.dp).novaRowPress(enabled = !loadingMore, onClick = onMore),
                            contentAlignment = Alignment.Center) {
                            NovaText(if (loadingMore) "Yükleniyor…" else "Daha fazla", style = NovaTypeToken.meta, color = ink)
                        }
                    }
                    Row(Modifier.fillMaxWidth().heightIn(min = 38.dp).novaRowPress { column.expanded = !column.expanded },
                        horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                        NovaText(if (column.expanded) "Daha az" else "Tümünü gör", style = NovaTypeToken.meta, color = ink)
                        NovaIcon(if (column.expanded) "chevron.up" else "chevron.right", 11.dp, tint = ink)
                    }
                }
            }
        }
    }
}

@Composable
private fun DeadlineCard(row: NovaFollowupPage.Row, ink: Color, onInspect: () -> Unit) {
    val equipmentName = row.equipmentTypeLabel?.trim()?.takeIf { it.isNotEmpty() }
        ?: row.equipmentType?.let(NovaEquipmentWords::type) ?: "Ekipman"
    val detail = if (row.kind == "equipment") "$equipmentName · ${row.title}" else row.title
    val shape = RoundedCornerShape(13.dp)
    Row(Modifier.fillMaxWidth().shadow(3.dp, shape, ambientColor = Color.Black.copy(alpha = 0.04f), spotColor = Color.Black.copy(alpha = 0.04f))
        .background(NovaColorToken.surface.color(), shape)
        .novaRowPress(onClick = onInspect).testTag("nova.home.deadline.inspect.${row.key}").padding(8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText(row.typeTitle, style = NovaTypeToken.badge, color = ink, maxLines = 1)
            NovaText(detail, style = NovaTypeToken.bodyStrong, color = NovaColorToken.text.color(), maxLines = 2)
            NovaText(row.companyName, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color(), maxLines = 1)
            row.dueOn?.let { day ->
                NovaText(NovaDay.label(day), style = NovaTypeToken.badge, color = ink, maxLines = 1)
            }
        }
        Box(Modifier.size(26.dp).background(ink.copy(alpha = 0.10f), CircleShape), contentAlignment = Alignment.Center) {
            NovaIcon("chevron.right", 10.dp, tint = ink)
        }
    }
}
