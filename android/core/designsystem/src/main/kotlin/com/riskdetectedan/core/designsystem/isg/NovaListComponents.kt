package com.riskdetectedan.core.designsystem.isg

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Shared title/action layout. Accessibility text sizes stack the action below. */
@Composable
fun NovaListHeading(title: String, onBack: () -> Unit, modifier: Modifier = Modifier,
                    action: @Composable () -> Unit = {}) {
    if (novaFontScaleIsAccessibility()) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaPageHeading(title, onBack = onBack)
            action()
        }
    } else {
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaPageHeading(title, modifier = Modifier.weight(1f), onBack = onBack)
            action()
        }
    }
}

/** A compact, monochrome counter shared by module lists. */
@Composable
fun NovaListStat(title: String, symbol: String, value: String, modifier: Modifier = Modifier,
                 selected: Boolean = false, onClick: (() -> Unit)? = null) {
    val ink = NovaColorToken.text.color()
    Column(modifier.heightIn(min = 64.dp).clip(RoundedCornerShape(16.dp)).novaControlBackground(16.dp)
        .border(1.dp, if (selected) ink else Color.Transparent, RoundedCornerShape(16.dp))
        .then(if (onClick != null) Modifier.novaRowPress(onClick = onClick) else Modifier)
        .semantics(mergeDescendants = true) {
            contentDescription = "$title, $value"
            this.selected = selected
        }
        .padding(horizontal = 9.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(symbol, 15.dp, tint = ink)
            NovaSizedText(value, 19f, FontWeight.SemiBold, ink, maxLines = 1)
        }
        NovaSizedText(title, 10f, FontWeight.Medium, ink, Modifier.heightIn(min = 26.dp), maxLines = 2)
    }
}

@Composable
fun NovaListStat(title: String, symbol: String, value: Int, modifier: Modifier = Modifier,
                 selected: Boolean = false, onClick: (() -> Unit)? = null) =
    NovaListStat(title, symbol, value.toString(), modifier, selected, onClick)

/** In-card secondary action with a full 44dp target. */
@Composable
fun NovaCompactActionButton(title: String, symbol: String, modifier: Modifier = Modifier,
                            prominent: Boolean = false, enabled: Boolean = true, identifier: String? = null,
                            onClick: () -> Unit) {
    val ink = if (prominent) Color.White else NovaColorToken.text.color()
    val shape = RoundedCornerShape(14.dp)
    Row(modifier.fillMaxWidth().heightIn(min = 44.dp).clip(shape)
        .background(if (prominent) Color.Black else NovaColorToken.surfaceMuted.color(), shape)
        .border(1.dp, if (prominent) Color.Transparent else NovaColorToken.border.color(), shape)
        .novaPress(enabled = enabled, onClick = onClick)
        .then(if (identifier != null) Modifier.testTag(identifier) else Modifier)
        .graphicsAlpha(if (enabled) 1f else 0.45f).padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 15.dp, tint = ink)
        NovaSizedText(title, 11f, FontWeight.SemiBold, ink, maxLines = 1)
    }
}

/** One full-width answer for an empty list: what is missing, then the useful next step. */
@Composable
fun NovaEmptyState(title: String, message: String, modifier: Modifier = Modifier) {
    NovaCard(modifier.fillMaxWidth(), padding = 16) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaText(title, style = NovaTypeToken.cardTitle)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaIcon("lightbulb", 16.dp, Modifier.padding(top = 2.dp), tint = NovaColorToken.statusWarningInk.color())
                NovaText(message, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
        }
    }
}

/** One option in a chooser; null id is the unfiltered answer. */
data class NovaChooserOption(val id: String?, val title: String, val count: Int? = null,
                             val symbol: String? = null, val tone: NovaStatus = NovaStatus.Neutral) {
    val identity: String get() = id ?: "all"
}

/** The closed half of a chooser: field name, current answer, chevron. */
@Composable
fun NovaChooserButton(label: String, value: String, identifier: String, modifier: Modifier = Modifier,
                      symbol: String? = null, open: Boolean = false, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    val rotation by animateFloatAsState(if (open) 180f else 0f, NovaMotion.easeOut(NovaMotion.Duration.dropdown), label = "chooser")
    Column(modifier.fillMaxWidth().heightIn(min = 52.dp).clip(shape).novaControlBackground(14.dp)
        .border(if (open) 1.4.dp else 1.dp, if (open) NovaColorToken.accentInk.color() else NovaColorToken.border.color(), shape)
        .novaRowPress(onClick = onClick).testTag(identifier)
        .semantics { stateDescription = value }
        .padding(horizontal = 12.dp, vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        NovaSizedText(label, 10f, FontWeight.Medium, NovaColorToken.textSecondary.color())
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (symbol != null) NovaIcon(symbol, 13.dp, tint = NovaColorToken.accentInk.color())
            NovaSizedText(value, 13f, FontWeight.Medium, NovaColorToken.text.color(), Modifier.weight(1f), maxLines = 1)
            NovaIcon("chevron.down", 14.dp, Modifier.rotate(rotation), tint = NovaColorToken.textTertiary.color())
        }
    }
}

/** Search stays visible while choices scroll inside a bounded panel. */
@Composable
fun NovaChooserPanel(options: List<NovaChooserOption>, selected: String?, identifier: String,
                     modifier: Modifier = Modifier, onPick: (String?) -> Unit) {
    var search by remember(identifier) { mutableStateOf("") }
    val locale = remember { java.util.Locale.forLanguageTag("tr-TR") }
    val matches = remember(options, search) {
        val query = search.trim().lowercase(locale)
        if (query.isEmpty()) options else options.filter { it.title.lowercase(locale).contains(query) }
    }
    Column(modifier.fillMaxWidth().novaControlBackground(16.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 40.dp)
            .background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(10.dp)).padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaIcon("magnifyingglass", 15.dp)
            Box(Modifier.weight(1f)) {
                if (search.isEmpty()) NovaSizedText("Ara…", 13f, FontWeight.Normal, NovaColorToken.textPlaceholder.color())
                BasicTextField(search, { search = it }, Modifier.fillMaxWidth().testTag("$identifier.search")
                    .semantics { contentDescription = "Seçeneklerde ara" }, singleLine = true,
                    textStyle = TextStyle(fontFamily = NovaFontFamilyPublic, fontSize = 13.sp, color = NovaColorToken.text.color()),
                    cursorBrush = SolidColor(NovaColorToken.text.color()))
            }
            if (search.isNotEmpty()) Box(Modifier.size(32.dp).novaPress(onClickLabel = "Aramayı temizle") { search = "" },
                contentAlignment = Alignment.Center) { NovaIcon("xmark", 14.dp) }
        }
        Column(Modifier.heightIn(max = 220.dp).verticalScroll(rememberScrollState())) {
            if (matches.isEmpty()) Box(Modifier.fillMaxWidth().heightIn(min = 44.dp), contentAlignment = Alignment.Center) {
                NovaText("Sonuç bulunamadı", style = NovaTypeToken.metaQuiet)
            }
            matches.forEach { option ->
                val on = selected == option.id
                val shade by animateFloatAsState(if (on) 1f else 0f, NovaMotion.easeOut(0.14), label = "chooserRow")
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp))
                    .background(NovaColorToken.surfaceMuted.color().copy(alpha = shade), RoundedCornerShape(10.dp))
                    .novaRowPress { onPick(option.id) }.testTag("$identifier.${option.identity}")
                    .semantics { this.selected = on }
                    .padding(horizontal = 10.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (option.symbol != null) NovaIcon(option.symbol, 15.dp, Modifier.width(18.dp))
                    NovaSizedText(option.title, 13f, if (on) FontWeight.SemiBold else FontWeight.Normal,
                        NovaColorToken.text.color(), Modifier.weight(1f))
                    if (option.count != null) NovaText(option.count.toString(), style = NovaTypeToken.micro)
                    NovaIcon("checkmark", 14.dp, Modifier.graphicsAlpha(if (on) 1f else 0f))
                }
            }
        }
    }
}

/** A single filter: the same searchable panel as multi-filter rows, grown from its button. */
@Composable
fun NovaFilterField(label: String, options: List<NovaChooserOption>, selected: String?, identifier: String,
                    modifier: Modifier = Modifier, onPick: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val reduceMotion = rememberNovaReduceMotion()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaChooserButton(label, options.firstOrNull { it.id == selected }?.title ?: "Tümü", identifier,
            open = expanded) { expanded = !expanded }
        AnimatedVisibility(expanded,
            enter = fadeIn(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion)) +
                if (reduceMotion) fadeIn(NovaMotion.easeOut(0.0)) else scaleIn(NovaMotion.easeOut(NovaMotion.Duration.dropdown), 0.97f, TransformOrigin(0.5f, 0f)),
            exit = fadeOut(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion)) +
                if (reduceMotion) fadeOut(NovaMotion.easeOut(0.0)) else scaleOut(NovaMotion.easeOut(NovaMotion.Duration.dropdown), 0.97f, TransformOrigin(0.5f, 0f))) {
            NovaChooserPanel(options, selected, "$identifier.options") { value ->
                onPick(value)
                expanded = false
            }
        }
    }
}

internal fun Modifier.graphicsAlpha(alpha: Float): Modifier = if (alpha >= 1f) this else this.alpha(alpha)
