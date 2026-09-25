package com.riskdetectedan.core.designsystem.isg

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The colour family of a choice: its tile, its level bars and the dot next to the chosen value (iOS `NovaChoiceTone`). */
enum class NovaChoiceTone {
    Neutral, Success, Warning, Danger;

    @Composable fun ink(): Color = when (this) {
        Neutral -> NovaColorToken.accentInk.color()
        Success -> NovaColorToken.statusSuccessInk.color()
        Warning -> NovaColorToken.statusWarningInk.color()
        Danger -> NovaColorToken.statusDangerInk.color()
    }

    @Composable fun soft(): Color = when (this) {
        Neutral -> NovaColorToken.surfaceMuted.color()
        Success -> NovaColorToken.statusSuccessBg.color()
        Warning -> NovaColorToken.statusWarningBg.color()
        Danger -> NovaColorToken.statusDangerBg.color()
    }
}

/**
 * One choice in a [NovaChoiceField] sheet (iOS `NovaChoiceOption`). [level] 1..3 draws rising level bars in the
 * tile (for ordered choices such as hazard classes); null draws [symbol].
 */
data class NovaChoiceOption<T>(
    val value: T,
    val title: String,
    val detail: String? = null,
    val tone: NovaChoiceTone = NovaChoiceTone.Neutral,
    val level: Int? = null,
    val symbol: String? = null,
)

/**
 * A form row that opens a bottom sheet of large, described choices (iOS `NovaChoiceField`). Nothing is chosen
 * until the user picks one: the row shows [placeholder], and the sheet closes on its own right after a pick.
 * Long lists get a search field and open full height; an optional field offers [noneTitle] as its first row
 * and reports it as null. [identifier] tags the row, "<identifier>.option.<index>", ".none" and ".search".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> NovaChoiceField(title: String, placeholder: String, symbol: String, options: List<NovaChoiceOption<T>>,
                        selection: T?, onSelect: (T?) -> Unit, identifier: String, modifier: Modifier = Modifier,
                        message: String? = null, enabled: Boolean = true, noneTitle: String? = null,
                        searchable: Boolean = options.size > 8,
                        /** A bordered field box (like [NovaChooserButton]) for forms of boxes; otherwise a plain row for a card with dividers. */
                        boxed: Boolean = false,
                        /** The sheet's heading when it should differ from [placeholder] (e.g. a placeholder that reads as a value). */
                        heading: String? = null,
                        /** Opens the sheet from outside, e.g. right after the step that needs this answer; reset through [onOpened]. */
                        openRequest: Boolean = false, onOpened: () -> Unit = {}) {
    var choosing by remember { mutableStateOf(false) }
    LaunchedEffect(openRequest) { if (openRequest && enabled) { choosing = true; onOpened() } }
    val chosen = options.firstOrNull { it.value == selection }
    val box = RoundedCornerShape(14.dp)
    Row(modifier.fillMaxWidth().heightIn(min = if (boxed) 52.dp else 48.dp).alpha(if (enabled) 1f else 0.5f)
        .then(if (boxed) Modifier.clip(box).novaControlBackground(14.dp).border(1.dp, NovaColorToken.border.color(), box) else Modifier)
        .novaRowPress(enabled = enabled) { choosing = true }.testTag(identifier)
        .semantics(mergeDescendants = true) { stateDescription = chosen?.title ?: noneTitle ?: placeholder }
        .then(if (boxed) Modifier.padding(horizontal = 12.dp) else Modifier),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) { NovaIcon(symbol, 17.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (chosen != null) {
                NovaText(title, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color())
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    if (chosen.tone != NovaChoiceTone.Neutral || chosen.level != null) Box(Modifier.size(8.dp).background(chosen.tone.ink(), CircleShape))
                    NovaText(chosen.title, style = NovaTypeToken.body, maxLines = 2)
                }
            } else if (noneTitle != null) {
                NovaText(title, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color())
                NovaText(noneTitle, style = NovaTypeToken.body, color = NovaColorToken.textSecondary.color())
            } else {
                NovaText(placeholder, style = NovaTypeToken.body, color = NovaColorToken.textPlaceholder.color())
            }
        }
        Box(Modifier.size(26.dp).background(NovaColorToken.surfaceMuted.color(), CircleShape).clearAndSetSemantics {},
            contentAlignment = Alignment.Center) {
            NovaIcon("chevron.down", 11.dp, tint = NovaColorToken.textMuted.color())
        }
    }
    if (choosing) {
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val scope = rememberCoroutineScope()
        val view = LocalView.current
        var query by remember { mutableStateOf("") }
        fun pick(value: T?) {
            onSelect(value)
            NovaHaptics.selection(view)
            // Long enough to see the tick land, short enough to feel instant.
            scope.launch { delay(220); sheet.hide() }.invokeOnCompletion { choosing = false }
        }
        val needle = query.trim()
        val found = options.withIndex().filter { (_, option) ->
            needle.isEmpty() || option.title.contains(needle, ignoreCase = true) || option.detail?.contains(needle, ignoreCase = true) == true
        }
        ModalBottomSheet(onDismissRequest = { choosing = false }, sheetState = sheet,
            containerColor = NovaColorToken.canvasSheet.color()) {
            Column(Modifier.fillMaxWidth().then(if (searchable) Modifier.fillMaxHeight(0.92f) else Modifier)
                .padding(start = 20.dp, end = 20.dp, top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    // A field's name may serve as the heading; its required mark does not belong there.
                    NovaText((heading ?: placeholder).removeSuffix(" *"), style = NovaTypeToken.sheetTitle, modifier = Modifier.semantics { heading() })
                    if (message != null) NovaText(message, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
                }
                if (searchable) ChoiceSearch(query, { query = it }, "$identifier.search")
                val none: @Composable () -> Unit = {
                    if (noneTitle != null && needle.isEmpty()) {
                        ChoiceCard(NovaChoiceOption(null, noneTitle), picked = selection == null, identifier = "$identifier.none") { pick(null) }
                    }
                }
                val empty: @Composable () -> Unit = {
                    if (found.isEmpty()) NovaText("Sonuç bulunamadı", Modifier.fillMaxWidth().padding(vertical = 24.dp),
                        NovaTypeToken.metaQuiet, NovaColorToken.textSecondary.color(), textAlign = TextAlign.Center)
                }
                // Long lists (people, workplaces) draw only the rows on screen.
                if (searchable) LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    item { none() }
                    items(found, key = { it.index }) { (index, option) ->
                        ChoiceCard(option, picked = option.value == selection, identifier = "$identifier.option.$index") { pick(option.value) }
                    }
                    item { empty() }
                } else Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(bottom = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    none()
                    found.forEach { (index, option) ->
                        ChoiceCard(option, picked = option.value == selection, identifier = "$identifier.option.$index") { pick(option.value) }
                    }
                    empty()
                }
            }
        }
    }
}

/** The sheet's search box (the same look as [NovaChooserPanel]'s). */
@Composable
private fun ChoiceSearch(query: String, onChange: (String) -> Unit, identifier: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 46.dp).background(NovaColorToken.surface.color(), RoundedCornerShape(14.dp))
        .border(1.dp, NovaColorToken.borderMuted.color(), RoundedCornerShape(14.dp)).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaIcon("magnifyingglass", 15.dp, tint = NovaColorToken.textMuted.color())
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) NovaText("Ara", style = NovaTypeToken.body, color = NovaColorToken.textPlaceholder.color())
            BasicTextField(query, onChange, Modifier.fillMaxWidth().testTag(identifier).semantics { contentDescription = "Seçeneklerde ara" },
                singleLine = true, textStyle = TextStyle(fontFamily = NovaFontFamilyPublic, fontSize = 14.sp, color = NovaColorToken.text.color()),
                cursorBrush = SolidColor(NovaColorToken.text.color()))
        }
        if (query.isNotEmpty()) Box(Modifier.size(32.dp).novaPress(onClickLabel = "Aramayı temizle") { onChange("") },
            contentAlignment = Alignment.Center) { NovaIcon("xmark", 14.dp) }
    }
}

/** A described choice is a large card with a tile; a plain one (a workplace, a person) is a compact row with the same tick. */
@Composable
private fun <T> ChoiceCard(option: NovaChoiceOption<T>, picked: Boolean, identifier: String, onClick: () -> Unit) {
    val ink = option.tone.ink()
    val shape = RoundedCornerShape(18.dp)
    val tick by animateFloatAsState(if (picked) 1f else 0f, label = "choice.tick")
    val hasTile = option.level != null || option.symbol != null
    val plain = !hasTile && option.detail == null
    val pickedBackground = if (option.tone == NovaChoiceTone.Neutral) NovaColorToken.accentSoft.color() else option.tone.soft().copy(alpha = 0.55f)
    Row(Modifier.fillMaxWidth().heightIn(min = if (plain) 52.dp else 0.dp).clip(shape)
        .background(if (picked) pickedBackground else NovaColorToken.surface.color(), shape)
        .border(if (picked) 1.5.dp else 1.dp, if (picked) ink else NovaColorToken.borderMuted.color(), shape)
        .novaRowPress(role = Role.RadioButton, onClick = onClick).testTag(identifier)
        .semantics(mergeDescendants = true) { selected = picked }
        .padding(horizontal = 14.dp, vertical = if (plain) 12.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        if (hasTile) Box(Modifier.size(46.dp).background(option.tone.soft(), RoundedCornerShape(13.dp)).clearAndSetSemantics {},
            contentAlignment = Alignment.Center) {
            val level = option.level
            if (level != null) Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                (1..3).forEach { bar ->
                    Box(Modifier.width(5.dp).height((6 + bar * 5).dp)
                        .background(if (bar <= level) ink else ink.copy(alpha = 0.22f), CircleShape))
                }
            } else option.symbol?.let { NovaIcon(it, 18.dp, tint = ink) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText(option.title, style = if (plain) NovaTypeToken.body else NovaTypeToken.cardTitle)
            option.detail?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color()) }
        }
        Box(Modifier.size(24.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            Box(Modifier.matchParentSize().border(1.5.dp, NovaColorToken.border.color(), CircleShape))
            Box(Modifier.matchParentSize().scale(tick).background(ink, CircleShape), contentAlignment = Alignment.Center) {
                NovaIcon("checkmark", 11.dp, tint = Color.White)
            }
        }
    }
}

/** Hazard classes as described choices (iOS `NovaHazardChoice`), keyed by the stored ids "low", "medium", "high". */
object NovaHazardChoice {
    const val placeholder = "Tehlike sınıfı seçin"
    const val message = "Resmî tehlike sınıfı, işyerinin NACE koduna göre belirlenir."
    val options: List<NovaChoiceOption<String>> = listOf(
        NovaChoiceOption("low", "Az Tehlikeli", "Risk değerlendirmesi 6 yılda bir yenilenir · en az C sınıfı uzman", NovaChoiceTone.Success, level = 1),
        NovaChoiceOption("medium", "Tehlikeli", "Risk değerlendirmesi 4 yılda bir yenilenir · en az B sınıfı uzman", NovaChoiceTone.Warning, level = 2),
        NovaChoiceOption("high", "Çok Tehlikeli", "Risk değerlendirmesi 2 yılda bir yenilenir · A sınıfı uzman", NovaChoiceTone.Danger, level = 3),
    )
}
