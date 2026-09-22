package com.riskdetectedan.core.designsystem.isg

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp

/** Shared chrome for long, consequential create/edit tasks. */
@Composable
fun NovaTaskHeader(title: String, step: Int, total: Int, stepTitle: String, modifier: Modifier = Modifier,
                   onClose: () -> Unit) {
    val progress by animateFloatAsState(step.toFloat() / total.coerceAtLeast(1),
        NovaMotion.easeOut(NovaMotion.Duration.progress), label = "taskProgress")
    Column(modifier, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onClose)
            NovaText(title, style = NovaTypeToken.screenTitle)
        }
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                NovaText("$step / $total", style = NovaTypeToken.label)
                Spacer(Modifier.weight(1f).widthIn(min = 10.dp))
                NovaText(stepTitle, style = NovaTypeToken.metaQuiet)
            }
            LinearProgressIndicator({ progress }, Modifier.fillMaxWidth().semantics {
                contentDescription = "İlerleme"
                stateDescription = "$step / $total, $stepTitle"
            }, color = NovaColorToken.accent.color(), trackColor = NovaColorToken.surfaceMuted.color(),
                strokeCap = StrokeCap.Round, gapSize = 0.dp, drawStopIndicator = {})
        }
    }
}

@Composable
fun NovaTaskErrorSummary(message: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().background(NovaColorToken.statusDangerBg.color(), RoundedCornerShape(14.dp))
        .semantics(mergeDescendants = true) {}.padding(13.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaIcon("exclamationmark.triangle.fill", 22.dp, tint = NovaColorToken.statusDangerInk.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText("Bu adımı kontrol edin", style = NovaTypeToken.bodyStrong)
            NovaText(message, style = NovaTypeToken.meta)
        }
    }
}

/** Keeps legal or explanatory copy out of the primary task path. */
@Composable
fun NovaWhyDisclosure(label: String = "Neden?", modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    val reduceMotion = rememberNovaReduceMotion()
    val rotation by animateFloatAsState(if (open) 180f else 0f, NovaMotion.easeOut(NovaMotion.Duration.dropdown), label = "why")
    Column(modifier.fillMaxWidth().novaControlBackground(14.dp).padding(12.dp).testTag("nova.why.disclosure")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 32.dp).novaRowPress { open = !open }
            .semantics { stateDescription = if (open) "Açık" else "Kapalı" },
            verticalAlignment = Alignment.CenterVertically) {
            NovaText(label, Modifier.weight(1f), style = NovaTypeToken.meta, color = NovaColorToken.text.color())
            NovaIcon("chevron.down", 14.dp, Modifier.rotate(rotation))
        }
        AnimatedVisibility(open, enter = fadeIn(NovaMotion.easeOut()) + expandVertically(NovaMotion.gated(NovaMotion.easeOut(), reduceMotion)),
            exit = fadeOut(NovaMotion.easeOut()) + shrinkVertically(NovaMotion.gated(NovaMotion.easeOut(), reduceMotion))) {
            Box(Modifier.padding(top = 6.dp)) { content() }
        }
    }
}

@Composable
fun NovaTaskStickyActions(primaryTitle: String, onBack: () -> Unit, onPrimary: () -> Unit,
                          modifier: Modifier = Modifier, primarySymbol: String = "arrow.right",
                          working: Boolean = false, canGoBack: Boolean = true) {
    val base = modifier.fillMaxWidth().shadow(10.dp, ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f))
        .background(NovaColorToken.surface.color()).padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 3.dp)
    if (novaFontScaleIsAccessibility()) Column(base, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (canGoBack) NovaButton("Geri", onBack, variant = NovaButtonVariant.Surface, symbol = "chevron.left")
        NovaButton(if (working) "Kaydediliyor…" else primaryTitle, onPrimary,
            symbol = if (working) "hourglass" else primarySymbol, enabled = !working)
    }
    else Row(base, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (canGoBack) NovaButton("Geri", onBack, Modifier.widthIn(max = 118.dp),
            variant = NovaButtonVariant.Surface, symbol = "chevron.left")
        NovaButton(if (working) "Kaydediliyor…" else primaryTitle, onPrimary, Modifier.weight(1f),
            symbol = if (working) "hourglass" else primarySymbol, enabled = !working)
    }
}

@Composable
fun NovaTaskSuccessView(title: String, message: String, doneTitle: String, onDone: () -> Unit,
                        nextTitle: String? = null, onNext: (() -> Unit)? = null) {
    NovaPageSurface {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)) {
            NovaIcon("checkmark.circle.fill", 54.dp, tint = NovaColorToken.accent.color())
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaText(title, style = NovaTypeToken.screenTitle)
                NovaText(message, style = NovaTypeToken.body)
            }
            if (nextTitle != null && onNext != null) {
                NovaCard(Modifier.fillMaxWidth(), padding = 15, tint = NovaColorToken.statusSuccessBg.color()) {
                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        NovaText("Sıradaki önerilen işlem", style = NovaTypeToken.metaQuiet)
                        NovaText(nextTitle, style = NovaTypeToken.bodyStrong)
                        NovaCompactActionButton(nextTitle, "arrow.right", prominent = true, onClick = onNext)
                    }
                }
            }
            NovaButton(doneTitle, onDone, symbol = "checkmark")
        }
    }
}

data class NovaMetricStripItem(val id: String, val value: String, val label: String, val symbol: String,
                               val status: NovaStatus)

@Composable
fun NovaMetricStrip(items: List<NovaMetricStripItem>, modifier: Modifier = Modifier) {
    Row(modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { item ->
            val fill = if (item.status == NovaStatus.Neutral) NovaColorToken.surfaceMuted.color() else item.status.background.color()
            Row(Modifier.heightIn(min = 38.dp).background(fill, CircleShape).semantics(mergeDescendants = true) {}
                .padding(horizontal = 11.dp), horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                NovaIcon(item.symbol, 14.dp)
                NovaText(item.value, style = NovaTypeToken.bodyStrong)
                NovaText(item.label, style = NovaTypeToken.metaQuiet)
            }
        }
    }
}

/** One choice in the section tile row. */
data class NovaFolderTab(val id: String, val title: String, val symbol: String, val caption: String? = null)

/** Compact section navigation; the picked tile carries the same outline as a picked stat. */
@Composable
fun NovaFolderTabs(tabs: List<NovaFolderTab>, selection: String, onSelect: (String) -> Unit,
                   modifier: Modifier = Modifier, identifierPrefix: String = "folder.tab",
                   content: @Composable () -> Unit) {
    val haptics = rememberNovaHaptics()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            tabs.forEach { tab ->
                val on = tab.id == selection
                val outline by animateFloatAsState(if (on) 1f else 0f, NovaMotion.easeOut(NovaMotion.Duration.popover), label = "folderTab")
                val shape = RoundedCornerShape(16.dp)
                Column(Modifier.weight(1f).heightIn(min = 96.dp).clip(shape)
                    .background(NovaColorToken.surface.color(), shape)
                    .border(1.5.dp, NovaColorToken.text.color().copy(alpha = outline), shape)
                    .novaRowPress {
                        if (selection != tab.id) { haptics.selection(); onSelect(tab.id) }
                    }
                    .semantics { selected = on }.testTag("$identifierPrefix.${tab.id}")
                    .padding(horizontal = 4.dp, vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) { NovaIcon(tab.symbol, 18.dp) }
                    NovaText(tab.title, style = NovaTypeToken.badge, color = NovaColorToken.text.color(),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    if (tab.caption != null) NovaText(tab.caption, style = NovaTypeToken.micro, color = NovaColorToken.text.color())
                }
            }
        }
        Box(Modifier.fillMaxWidth().padding(horizontal = 2.dp).padding(bottom = 2.dp)) { content() }
    }
}
