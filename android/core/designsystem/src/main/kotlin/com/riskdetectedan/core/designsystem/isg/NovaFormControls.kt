package com.riskdetectedan.core.designsystem.isg

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** A labelled text input: one line, or a multi-line area on the muted field fill (iOS TextField/TextEditor). */
@Composable
fun NovaTextField(label: String, value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
                  identifier: String? = null, multiline: Boolean = false, placeholder: String = label,
                  keyboardType: KeyboardType = KeyboardType.Text, enabled: Boolean = true) {
    val ink = NovaColorToken.text.color()
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        NovaText(label, style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        Box(Modifier.fillMaxWidth().heightIn(min = if (multiline) 72.dp else 40.dp)
            .background(if (multiline) NovaColorToken.surfaceMuted.color() else Color.Transparent, RoundedCornerShape(10.dp))
            .padding(horizontal = if (multiline) 10.dp else 0.dp, vertical = if (multiline) 8.dp else 8.dp)) {
            if (value.isEmpty()) NovaText(placeholder, color = NovaColorToken.textPlaceholder.color())
            BasicTextField(value, onValueChange, Modifier.fillMaxWidth()
                .then(if (identifier != null) Modifier.testTag(identifier) else Modifier)
                .semantics { contentDescription = label }, enabled = enabled, singleLine = !multiline,
                textStyle = novaTextStyle(NovaTypeToken.body).copy(color = ink), cursorBrush = SolidColor(ink),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, keyboardType = keyboardType))
        }
    }
}

/** A segmented choice (iOS `.pickerStyle(.segmented)`). */
@Composable
fun <T> NovaSegmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier,
                      identifier: String? = null) {
    val haptics = rememberNovaHaptics()
    Row(modifier.fillMaxWidth().heightIn(min = 40.dp).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(10.dp))
        .padding(3.dp).then(if (identifier != null) Modifier.testTag(identifier) else Modifier),
        horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        options.forEach { (value, title) ->
            val on = value == selected
            val fill by animateFloatAsState(if (on) 1f else 0f, NovaMotion.easeOut(0.14), label = "segment")
            Box(Modifier.weight(1f).heightIn(min = 36.dp).clip(RoundedCornerShape(8.dp))
                .background(NovaColorToken.surface.color().copy(alpha = fill), RoundedCornerShape(8.dp))
                .novaRowPress(role = Role.Tab) { if (!on) { haptics.selection(); onSelect(value) } }
                .semantics { this.selected = on }.padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
                NovaSizedText(title, 12.5f, if (on) FontWeight.SemiBold else FontWeight.Medium, NovaColorToken.text.color(),
                    maxLines = 1, textAlign = TextAlign.Center)
            }
        }
    }
}

/** A choice chip: capsule, filled green when chosen. */
@Composable
fun NovaChoiceChip(title: String, selected: Boolean, modifier: Modifier = Modifier, identifier: String? = null,
                   inverse: Boolean = false, onClick: () -> Unit) {
    val fill by animateFloatAsState(if (selected) 1f else 0f, NovaMotion.easeOut(0.14), label = "chip")
    val onFill = if (inverse) NovaColorToken.inverse.color() else NovaColorToken.statusSuccessBg.color()
    // Inside a popup the surrounding card is already the muted fill, so an idle chip takes the surface.
    val offFill = (if (LocalNovaPopup.current) NovaColorToken.surface else NovaColorToken.surfaceMuted).color()
    val ink = if (selected) (if (inverse) NovaColorToken.onInverse.color() else NovaColorToken.accentInk.color())
        else if (inverse) NovaColorToken.text.color() else NovaColorToken.textSecondary.color()
    val shape = if (inverse) RoundedCornerShape(10.dp) else CircleShape
    Box(modifier.heightIn(min = 40.dp).widthIn(min = 44.dp).clip(shape)
        .background(androidx.compose.ui.graphics.lerp(offFill, onFill, fill), shape)
        .novaRowPress { onClick() }.semantics { this.selected = selected }
        .then(if (identifier != null) Modifier.testTag(identifier) else Modifier)
        .padding(horizontal = if (inverse) 14.dp else 12.dp), contentAlignment = Alignment.Center) {
        NovaText(title, style = NovaTypeToken.meta, color = ink)
    }
}

/** Radio-style row used by company and workplace pickers. */
@Composable
fun NovaRadioRow(title: String, selected: Boolean, detail: String? = null, identifier: String? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress(onClick = onClick)
        .semantics { this.selected = selected }.then(if (identifier != null) Modifier.testTag(identifier) else Modifier),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaIcon(if (selected) "checkmark.circle.fill" else "circle", 20.dp,
            tint = if (selected) NovaColorToken.accentInk.color() else NovaColorToken.borderStrong.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            NovaText(title, style = if (detail != null) NovaTypeToken.cardTitle else NovaTypeToken.body)
            if (!detail.isNullOrEmpty()) NovaText(detail, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
        }
    }
}

enum class NovaCompletionState { missing, complete, needsReview, unknown }

/** The company headings whose completion the score counts (iOS `NovaCompanySection`). */
enum class NovaCompanySection(val title: String, val symbol: String) {
    logo("Firma Logosu", "photo"), personnel("Personel Listesi", "person.2"),
    representative("Çalışan Temsilcisi", "person.crop.rectangle"), support("Destek Elemanları", "person.3"),
    risk("Risk Analizi", "exclamationmark.triangle"), emergency("Acil Durum Eylem Planı", "shield"),
    inspections("Periyodik Kontroller", "wrench.and.screwdriver"), accidents("İş Kazaları", "cross.case"),
    board("İSG Kurulu", "person.3.sequence"), training("Eğitimler", "graduationcap"), files("Dosyalarım", "folder"),
    handover("Zimmet Formları", "doc.text"),
}

/** Collapsible heading used by the company page and the stepwise forms. */
@Composable
fun NovaCompanyAccordion(title: String, symbol: String, expanded: Boolean, onToggle: (Boolean) -> Unit,
                         modifier: Modifier = Modifier, state: NovaCompletionState? = null, identifier: String = "company.accordion",
                         outlinesWhenExpanded: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    val reduceMotion = rememberNovaReduceMotion()
    val rotation by animateFloatAsState(if (expanded) 180f else 0f, NovaMotion.gated(NovaMotion.easeInOut(0.2), reduceMotion), label = "accordion")
    NovaCard(modifier.fillMaxWidth(), padding = 10,
        border = if (expanded && outlinesWhenExpanded) NovaColorToken.textSecondary.color() else Color.Transparent) {
        Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).clip(RoundedCornerShape((NovaDimensionToken.radiusCard.value - 2).dp))
            .background(if (expanded) NovaColorToken.surfaceMuted.color() else Color.Transparent,
                RoundedCornerShape((NovaDimensionToken.radiusCard.value - 2).dp))
            .novaRowPress { onToggle(!expanded) }.testTag(identifier)
            .semantics { stateDescription = if (expanded) "Açık" else "Kapalı" }.padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            NovaIcon(symbol, 19.dp, tint = accordionTone(symbol).color())
            NovaText(title, Modifier.weight(1f), NovaTypeToken.label)
            if (state != null && state != NovaCompletionState.unknown) {
                val complete = state == NovaCompletionState.complete
                Row(Modifier.background((if (complete) NovaColorToken.statusSuccessBg else NovaColorToken.statusDangerBg).color(), CircleShape)
                    .padding(horizontal = 8.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(3.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    val ink = (if (complete) NovaColorToken.accentInk else NovaColorToken.statusDangerInk).color()
                    NovaIcon(if (complete) "checkmark" else "xmark", 11.dp, tint = ink)
                    NovaSizedText(if (complete) "Tamamlandı" else "Eksik", 10f, FontWeight.SemiBold, ink)
                }
            }
            NovaIcon("chevron.down", 14.dp, Modifier.rotate(rotation))
        }
        AnimatedVisibility(expanded, enter = fadeIn(NovaMotion.gated(NovaMotion.easeInOut(0.2), reduceMotion)) +
                expandVertically(NovaMotion.gated(NovaMotion.easeInOut(0.2), reduceMotion), Alignment.Top),
            exit = fadeOut(NovaMotion.gated(NovaMotion.easeInOut(0.2), reduceMotion)) +
                shrinkVertically(NovaMotion.gated(NovaMotion.easeInOut(0.2), reduceMotion), Alignment.Top)) {
            Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
        }
    }
}

private fun accordionTone(symbol: String): NovaColorToken = when (symbol) {
    "exclamationmark.triangle", "wrench.and.screwdriver" -> NovaColorToken.statusWarningInk
    "shield", "graduationcap", "folder", "doc.text" -> NovaColorToken.statusInfoInk
    "person.2", "person.crop.rectangle", "person.3", "person.3.sequence" -> NovaColorToken.accentInk
    "cross.case" -> NovaColorToken.statusDangerInk
    else -> NovaColorToken.text
}

enum class NovaCompanyReadinessStatus(val title: String) {
    complete("Tamamlandı"), needsReview("Kontrol gerekli"), missing("Eksik"), unknown("Veri bekleniyor");
    @Composable fun color(): Color = when (this) {
        complete -> NovaColorToken.accent.color()
        needsReview -> Color(0.70f, 0.62f, 0.94f)
        missing -> Color(1f, 0.38f, 0.20f)
        unknown -> NovaColorToken.border.color()
    }
}

data class NovaCompanyReadinessItem(val id: String, val title: String, val detail: String, val status: NovaCompanyReadinessStatus)

/** The ten operational headings as one segmented ring (iOS `NovaCompanyReadinessCard`). */
@Composable
fun NovaCompanyReadinessCard(items: List<NovaCompanyReadinessItem>, modifier: Modifier = Modifier) {
    var selectedId by remember { mutableStateOf<String?>(null) }
    val suggested = items.firstOrNull { it.status == NovaCompanyReadinessStatus.needsReview }
        ?: items.firstOrNull { it.status == NovaCompanyReadinessStatus.missing }
        ?: items.firstOrNull { it.status == NovaCompanyReadinessStatus.unknown } ?: items.firstOrNull()
    val selected = items.firstOrNull { it.id == selectedId } ?: suggested
    val completed = items.count { it.status == NovaCompanyReadinessStatus.complete }
    val legend = NovaCompanyReadinessStatus.entries.filter { it != NovaCompanyReadinessStatus.unknown || items.any { i -> i.status == it } }
    NovaCard(modifier.fillMaxWidth().testTag("company.progress"), padding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(15.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                NovaText("Firma İlerlemesi", Modifier.weight(1f), NovaTypeToken.sectionTitle)
                Box(Modifier.heightIn(min = 38.dp).background(NovaColorToken.surface.color(), CircleShape)
                    .border(1.dp, NovaColorToken.border.color(), CircleShape).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                    NovaSizedText("${items.size} başlık", 11f, FontWeight.SemiBold, NovaColorToken.textSecondary.color())
                }
            }
            if (selected != null) Row(Modifier.align(Alignment.CenterHorizontally).heightIn(min = 36.dp)
                .background(Color(0.04f, 0.035f, 0.09f), CircleShape).padding(horizontal = 13.dp)
                .semantics(mergeDescendants = true) { contentDescription = "${selected.title}, ${selected.status.title}. ${selected.detail}" },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(8.dp).background(selected.status.color(), CircleShape))
                NovaSizedText("${selected.title} · ${selected.status.title}", 11f, FontWeight.SemiBold, Color.White, maxLines = 1)
            }
            val ring = @Composable {
                val colors = items.map { it.status.color() }
                val reduceMotion = rememberNovaReduceMotion()
                Box(Modifier.size(142.dp), contentAlignment = Alignment.Center) {
                    Canvas(Modifier.fillMaxSize().semantics {
                        contentDescription = "Firma ilerlemesi, $completed / ${items.size} başlık tamamlandı"
                    }.pointerInput(items) {
                        detectTapGestures { point ->
                            val dx = point.x - size.width / 2f
                            val dy = point.y - size.height / 2f
                            val degrees = (Math.toDegrees(kotlin.math.atan2(dy, dx).toDouble()) + 90 + 360) % 360
                            val index = (degrees / (360.0 / items.size.coerceAtLeast(1))).toInt()
                            items.getOrNull(index)?.let { selectedId = it.id }
                        }
                    }) {
                        val count = items.size.coerceAtLeast(1)
                        val sweep = 360f / count
                        val stroke = size.minDimension * 0.17f
                        items.forEachIndexed { index, item ->
                            val grow = if (item.id == selected?.id && !reduceMotion) 1.035f else 1f
                            val inset = stroke / 2 + (1 - grow) * size.minDimension / 2
                            drawArc(colors[index], -90f + index * sweep + 1.4f, sweep - 2.8f, false,
                                topLeft = Offset(inset, inset), size = Size(size.width - inset * 2, size.height - inset * 2),
                                style = Stroke(stroke, cap = StrokeCap.Butt))
                        }
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        NovaSizedText("$completed/${items.size}", 27f, FontWeight.Bold)
                        NovaText("tamamlandı", style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color())
                    }
                }
            }
            val legendView = @Composable { m: Modifier ->
                Column(m, verticalArrangement = Arrangement.spacedBy(13.dp)) {
                    legend.forEach { status ->
                        Row(Modifier.fillMaxWidth().novaRowPress { items.firstOrNull { it.status == status }?.let { selectedId = it.id } },
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.size(9.dp).background(status.color(), CircleShape))
                            NovaText(status.title, Modifier.weight(1f), NovaTypeToken.metaQuiet)
                            NovaSizedText(items.count { it.status == status }.toString(), 14f, FontWeight.SemiBold)
                        }
                    }
                }
            }
            if (novaFontScaleIsAccessibility()) Column(horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp)) { ring(); legendView(Modifier.fillMaxWidth()) }
            else Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                ring(); legendView(Modifier.weight(1f))
            }
            Row(Modifier.fillMaxWidth().heightIn(min = 62.dp).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(18.dp))
                .padding(horizontal = 13.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaIcon("sparkles", 19.dp, tint = Color(0.29f, 0.20f, 0.77f))
                NovaText(readinessSummary(items), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            }
        }
    }
}

private fun readinessSummary(items: List<NovaCompanyReadinessItem>): String {
    val missing = items.filter { it.status == NovaCompanyReadinessStatus.missing }
    val review = items.filter { it.status == NovaCompanyReadinessStatus.needsReview }
    val unknown = items.filter { it.status == NovaCompanyReadinessStatus.unknown }
    if (missing.isEmpty() && review.isEmpty() && unknown.isEmpty()) return "Tüm firma başlıkları tamamlandı ve güncel görünüyor."
    val parts = mutableListOf<String>()
    if (missing.isNotEmpty()) {
        val names = missing.take(2).joinToString(" ve ") { it.title }
        parts += if (missing.size > 2) "$names dahil ${missing.size} başlık eksik" else "$names eksik"
    }
    if (review.isNotEmpty()) parts += "${review.size} başlığın tarihi veya durumu kontrol edilmeli"
    if (unknown.isNotEmpty()) parts += "${unknown.size} başlık için veri bekleniyor"
    return parts.joinToString(". ") + "."
}
