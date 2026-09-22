package com.riskdetectedan.core.designsystem.isg

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** ISO day helpers (iOS `NovaDayField.text/date` and `NovaStatisticsSnapshot.dayLabel`). */
object NovaDay {
    fun today(): String = LocalDate.now(java.time.ZoneId.of("Europe/Istanbul")).toString()
    fun parse(text: String): LocalDate? = runCatching { LocalDate.parse(text) }.getOrNull()
    /** 2026-09-22 reads 22.09.2026; anything else is shown as it came. */
    fun label(value: String): String {
        val parts = value.split('-')
        return if (parts.size == 3) "${parts[2]}.${parts[1]}.${parts[0]}" else value
    }
}

/** A labelled day picker that stores the ISO day the server keeps (iOS `NovaDayField`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NovaDayField(label: String, value: String, onValueChange: (String) -> Unit, identifier: String,
                 modifier: Modifier = Modifier, clearable: Boolean = false, symbol: String = "calendar") {
    var picking by remember { mutableStateOf(false) }
    NovaFormValueRow(label, symbol, modifier) {
        if (clearable && value.isEmpty()) {
            Box(Modifier.heightIn(min = 36.dp).novaRowPress { onValueChange(NovaDay.today()) }.testTag("$identifier.set"),
                contentAlignment = Alignment.Center) { NovaText("Belirtilmedi", style = NovaTypeToken.meta) }
        } else Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.heightIn(min = 36.dp).clip(RoundedCornerShape(8.dp))
                .background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(8.dp))
                .novaRowPress { picking = true }.semantics { contentDescription = "$label, ${NovaDay.label(value)}" }
                .testTag(identifier).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                NovaText(NovaDay.label(value.ifEmpty { NovaDay.today() }), style = NovaTypeToken.bodyStrong)
            }
            if (clearable) Box(Modifier.size(32.dp).clip(CircleShape).novaRowPress { onValueChange("") }
                .semantics { contentDescription = "Tarihi temizle" }.testTag("$identifier.clear"), contentAlignment = Alignment.Center) {
                NovaIcon("xmark.circle", 15.dp, tint = NovaColorToken.textTertiary.color())
            }
        }
    }
    if (picking) {
        val initial = NovaDay.parse(value)?.atStartOfDay(ZoneOffset.UTC)?.toInstant()?.toEpochMilli()
        val state = rememberDatePickerState(initialSelectedDateMillis = initial ?: System.currentTimeMillis())
        val ink = NovaColorToken.text.color()
        val colors = DatePickerDefaults.colors(containerColor = NovaColorToken.surface.color(),
            selectedDayContainerColor = NovaColorToken.accent.color(), selectedDayContentColor = androidx.compose.ui.graphics.Color(0xFF111111),
            todayDateBorderColor = NovaColorToken.accentInk.color(), todayContentColor = NovaColorToken.accentInk.color(),
            titleContentColor = ink, headlineContentColor = ink, weekdayContentColor = NovaColorToken.textSecondary.color(),
            dayContentColor = ink, navigationContentColor = ink, yearContentColor = ink,
            selectedYearContainerColor = NovaColorToken.accent.color(), currentYearContentColor = NovaColorToken.accentInk.color())
        DatePickerDialog(onDismissRequest = { picking = false }, colors = colors, confirmButton = {
            TextButton({
                state.selectedDateMillis?.let { onValueChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) }
                picking = false
            }) { NovaText("Tamam", style = NovaTypeToken.button, color = NovaColorToken.accentInk.color()) }
        }, dismissButton = {
            TextButton({ picking = false }) { NovaText("Vazgeç", style = NovaTypeToken.button, color = NovaColorToken.textSecondary.color()) }
        }) { DatePicker(state, colors = colors, showModeToggle = false) }
    }
}

/** A small status tag: icon and word on the status tint (iOS `NovaAnalysisTag`). */
@Composable
fun NovaTag(symbol: String, text: String, status: NovaStatus = NovaStatus.Neutral, modifier: Modifier = Modifier) {
    val ink = status.ink.color()
    Row(modifier.background(status.background.color(), CircleShape).padding(horizontal = 8.dp, vertical = 5.dp)
        .semantics(mergeDescendants = true) { contentDescription = text },
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 10.dp, tint = ink)
        NovaText(text, style = NovaTypeToken.micro, color = ink)
    }
}
