package com.riskdetectedan.feature.nova

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * One analysis item in full, as a popup (iOS `NovaAnalysisItemSheet`): the picture it was read from, its score, and
 * every field. Only scored findings have an editable record behind them.
 */
@Composable
private fun NovaAnalysisItemSheet(item: NovaAnalysisItem, section: NovaAnalysisSectionKind, method: NovaRiskMethod, photo: ByteArray?,
                                  subtitle: String, reaction: NovaAnalysisReaction, canWrite: Boolean,
                                  react: suspend (NovaAnalysisReaction) -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var chosen by remember(item.id) { mutableStateOf(reaction) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val picture = remember(photo) { photo?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
    val band = item.band(method)
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Box(Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(20.dp)).background(NovaColorToken.surfaceMuted.color())) {
            if (picture != null) Image(picture.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else NovaIcon("photo", 30.dp, Modifier.align(Alignment.Center), tint = NovaColorToken.textTertiary.color())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to NovaColorToken.inverse.color().copy(alpha = 0.88f))))
            Column(Modifier.align(Alignment.BottomStart).padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (band != null) NovaStatusPill(NovaNonconformityWords.band(band), NovaNonconformityWords.tone(band), showsDot = false)
                    else NovaStatusPill("Skorsuz", NovaStatus.Info, showsDot = false)
                    NovaText("Kayıt #${item.ordinal}", Modifier.weight(1f), NovaTypeToken.micro, color = NovaColorToken.onInverse.color().copy(alpha = 0.8f))
                    item.value(method)?.let { NovaText(NovaNonconformityWords.score(it), style = NovaTypeToken.sheetTitle, color = NovaColorToken.onInverse.color()) }
                }
                NovaText(item.title, style = NovaTypeToken.cardTitle, color = NovaColorToken.onInverse.color(), maxLines = 3)
                NovaText(subtitle, style = NovaTypeToken.micro, color = NovaColorToken.onInverse.color().copy(alpha = 0.72f), maxLines = 1)
            }
            if (canWrite) Row(Modifier.align(Alignment.TopEnd).padding(9.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(Triple(NovaAnalysisReaction.like, "hand.thumbsup", "Faydalı"), Triple(NovaAnalysisReaction.dislike, "hand.thumbsdown", "Faydasız"))
                    .forEach { (value, symbol, label) ->
                        val on = chosen == value
                        Box(Modifier.size(38.dp).clip(CircleShape).background(NovaColorToken.surface.color().copy(alpha = 0.9f))
                            .novaRowPress(enabled = !busy) {
                                val next = if (on) NovaAnalysisReaction.none else value
                                busy = true; error = null
                                coroutines.launch {
                                    try { react(next); chosen = next } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                                        error = "Geri bildirim kaydedilemedi. Tekrar deneyin."
                                    }
                                    busy = false
                                }
                            }.semantics { contentDescription = label }.testTag("analysis.item.${value.name}"), contentAlignment = Alignment.Center) {
                            NovaIcon(if (on) "$symbol.fill" else symbol, 14.dp, tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.text.color())
                        }
                    }
            }
        }
        if (canWrite && section.isScored) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(Triple("square.and.pencil", "Bulguyu düzenle", NovaStatus.Neutral) to onEdit, Triple("trash", "Bulguyu sil", NovaStatus.Danger) to onDelete)
                .forEach { (words, action) ->
                    val (symbol, label, status) = words
                    Row(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(14.dp)).background(status.background.color()).novaRowPress(onClick = action),
                        horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(symbol, 13.dp, tint = status.ink.color()); NovaText(label, style = NovaTypeToken.meta, color = status.ink.color())
                    }
                }
        }
        val score = item.score(method)
        val value = score?.value
        if (score != null && value != null) {
            val tone = NovaNonconformityWords.tone(score.band)
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(tone.background.color()).padding(13.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    NovaText(NovaNonconformityWords.score(value), style = NovaTypeToken.screenTitle, color = tone.ink.color())
                    NovaText("PUAN", Modifier.weight(1f), NovaTypeToken.micro, color = tone.ink.color().copy(alpha = 0.8f))
                    NovaText(NovaNonconformityWords.method(method), style = NovaTypeToken.meta, color = tone.ink.color())
                }
                if (score.factors.isNotEmpty()) NovaText(score.factors.joinToString(" × ") { "${it.label} ${NovaNonconformityWords.score(it.value)}" } +
                    " = ${NovaNonconformityWords.score(value)}", style = NovaTypeToken.badge, color = tone.ink.color())
            }
        }
        @Composable fun panel(label: String, symbol: String, text: String?, status: NovaStatus) {
            val body = text?.trim()?.takeIf { it.isNotEmpty() } ?: return
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).novaControlBackground(16.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon(symbol, 11.dp, tint = status.ink.color())
                    NovaText(label.uppercase(java.util.Locale.forLanguageTag("tr-TR")), style = NovaTypeToken.overline, color = status.ink.color())
                }
                NovaText(body)
            }
        }
        panel("Açıklama", "text.alignleft", item.body, NovaNonconformityWords.tone(band))
        panel("Kimler için", "person.2", item.audience, NovaStatus.Info)
        panel("Kök neden", "magnifyingglass", item.rootCause, NovaStatus.Warning)
        if (item.measures.isEmpty()) panel("Düzeltici önlem", "checkmark.seal", item.measure, NovaStatus.Success)
        else item.measures.forEach { panel(it.title, if (it.isPreventive) "shield" else "checkmark.seal", it.text, if (it.isPreventive) NovaStatus.Info else NovaStatus.Success) }
        panel("Mevzuat", "book", item.references, NovaStatus.Info)
        if (item.durationValue != null && item.durationLabel != null)
            panel(item.durationLabel!!, "clock", listOfNotNull(item.durationValue, item.durationNote).joinToString("\n"), NovaStatus.Neutral)
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
    }
}

/**
 * A record born from a photo finding, opened from the board (iOS `NovaFiledFindingSheet`): it reuses the analysis
 * item sheet; when the source cannot be resolved the ordinary record sheet stands in.
 */
@Composable
internal fun NovaFiledFindingSheet(entry: NovaNonconformityEntry, identity: IsgWorkspaceIdentity, context: IsgWorkspaceContext?,
                                   analysis: NovaAnalysisService, canWrite: Boolean, fallback: @Composable () -> Unit) {
    var source by remember { mutableStateOf<NovaAnalysisService.RecordFinding?>(null) }
    var failed by remember { mutableStateOf(false) }
    var mode by remember { mutableStateOf("read") }
    var reload by remember { mutableIntStateOf(0) }
    LaunchedEffect(reload) {
        failed = false
        try {
            source = analysis.recordFinding(entry, identity, context, analysis.preferredMethod(identity))
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { failed = true }
    }
    val value = source
    when {
        value != null -> when (mode) {
            "edit" -> NovaAnalysisEditSheet(value.item, value.method, onCancel = { mode = "read" }) { change ->
                analysis.edit(change.copy(analysisId = value.analysisId, findingId = value.item.id), identity)
                mode = "read"; reload++
            }
            "delete" -> NovaAnalysisDeleteSheet(value.item, onCancel = { mode = "read" }) {
                analysis.remove(value.analysisId, value.item.id, identity)
                source = null; failed = true; mode = "read"
            }
            else -> NovaAnalysisItemSheet(value.item, value.section, value.method, value.photo,
                listOfNotNull(value.companyName, value.analysisTitle.ifEmpty { null }, value.createdOn.ifEmpty { null }).joinToString(" · "),
                value.item.reaction, canWrite, react = { reaction -> analysis.react(value.analysisId, value.item, value.section, reaction, identity) },
                onEdit = { mode = "edit" }, onDelete = { mode = "delete" })
        }
        failed -> fallback()
        else -> NovaLoadingView("Bulgu yükleniyor…")
    }
}
