package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.rememberTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

/**
 * How a centred popup arrives and leaves (iOS `NovaPopupTransition`): the
 * backdrop fades, the card scales from 0.94, the exit is the same path reversed
 * and the window is only removed once the card has left.
 */
object NovaPopupTransition {
    const val enterScale = 0.94f
    const val exitSeconds = 0.16
}

/** A form inside a popup reports a running save so the popup cannot be dismissed under it. */
val LocalNovaPopupBusy = staticCompositionLocalOf<(Boolean) -> Unit> { {} }

/** Content asks its own popup to close — the same exit as the X button. */
val LocalNovaPopupDismiss = staticCompositionLocalOf<() -> Unit> { {} }

/**
 * A centred, keyboard-safe modal (iOS `NovaPopup`). [visible] is the caller's
 * state; flipping it to false runs the exit before the window is torn down.
 * [onDismissRequest] asks the caller to flip it (X, back, scrim).
 */
@Composable
fun NovaPopup(visible: Boolean, onDismissRequest: () -> Unit, modifier: Modifier = Modifier,
              identifier: String = "nova.popup", scrollable: Boolean = true,
              content: @Composable ColumnScope.() -> Unit) {
    val state = remember { MutableTransitionState(false) }
    state.targetState = visible
    if (!state.currentState && !state.targetState && state.isIdle) return
    var busy by remember { mutableStateOf(false) }
    val reduceMotion = rememberNovaReduceMotion()
    val close = { if (!busy) onDismissRequest() }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false,
        decorFitsSystemWindows = false, dismissOnClickOutside = false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect { window?.setDimAmount(0f) }
        val transition = rememberTransition(state, label = "novaPopup")
        BoxWithConstraints(Modifier.fillMaxSize().imePadding(), contentAlignment = Alignment.Center) {
            transition.AnimatedVisibility({ it }, enter = fadeIn(NovaMotion.easeOut(0.24)),
                exit = fadeOut(NovaMotion.easeOut(NovaPopupTransition.exitSeconds))) {
                Box(Modifier.fillMaxSize()
                    .background(NovaColorToken.canvasSheet.color().copy(alpha = 0.45f * NovaPopupStyle.materialOpacity))
                    .background(Color.Black.copy(alpha = NovaPopupStyle.dimOpacity))
                    .clickable(remember { MutableInteractionSource() }, null, onClick = {}))
            }
            val maxCardHeight = (maxHeight - 32.dp).coerceAtLeast(140.dp)
            transition.AnimatedVisibility({ it },
                enter = fadeIn(NovaMotion.easeOut(0.24)) +
                    (if (reduceMotion) fadeIn(NovaMotion.easeOut(0.0)) else scaleIn(NovaMotion.easeOut(0.24), NovaPopupTransition.enterScale)),
                exit = fadeOut(NovaMotion.easeOut(NovaPopupTransition.exitSeconds)) +
                    (if (reduceMotion) fadeOut(NovaMotion.easeOut(0.0)) else scaleOut(NovaMotion.easeOut(NovaPopupTransition.exitSeconds), NovaPopupTransition.enterScale))) {
                Box(modifier.padding(horizontal = 16.dp).widthIn(max = 540.dp).fillMaxWidth().heightIn(max = maxCardHeight)
                    .shadow(24.dp, RoundedCornerShape(24.dp), ambientColor = Color.Black.copy(alpha = 0.12f),
                        spotColor = Color.Black.copy(alpha = 0.12f))
                    .clip(RoundedCornerShape(24.dp)).background(NovaPopupStyle.background()).testTag(identifier)) {
                    CompositionLocalProvider(LocalNovaPopup provides true,
                        LocalNovaPopupBusy provides { busy = it }, LocalNovaPopupDismiss provides close) {
                        Column(Modifier.padding(top = 40.dp)
                            .then(if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                            .padding(start = 16.dp, end = 16.dp, bottom = 16.dp), content = content)
                    }
                    NovaPopupCloseButton(Modifier.align(Alignment.TopEnd).padding(top = 8.dp, end = 8.dp),
                        enabled = !busy, onClick = close)
                }
            }
        }
        BackHandler(enabled = busy) {}
    }
}

/** A visible 48dp circular target; the whole circle closes. */
@Composable
fun NovaPopupCloseButton(modifier: Modifier = Modifier, identifier: String = "nova.popup.close",
                         enabled: Boolean = true, onClick: () -> Unit) {
    Box(modifier.size(48.dp).clip(CircleShape).background(NovaColorToken.surfaceMuted.color(), CircleShape)
        .border(1.dp, NovaColorToken.border.color(), CircleShape)
        .novaPress(enabled = enabled, scale = 0.92f, pressedAlpha = 0.72f, onClick = onClick)
        .semantics { contentDescription = "Kapat" }.testTag(identifier),
        contentAlignment = Alignment.Center) {
        NovaIcon("xmark", 17.dp)
    }
}

/** Heading for company pickers and forms inside a popup. */
@Composable
fun NovaPopupHeading(text: String, symbol: String = "square.and.pencil", subtitle: String? = null,
                     modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaIcon(symbol, 24.dp, Modifier.padding(2.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            NovaText(text, style = NovaTypeToken.sheetTitle)
            if (subtitle != null) NovaText(subtitle, style = NovaTypeToken.metaQuiet)
        }
    }
}

@Composable
fun NovaPopupOption(title: String, symbol: String, subtitle: String? = null, modifier: Modifier = Modifier,
                    identifier: String? = null, onClick: () -> Unit) {
    Row(modifier.fillMaxWidth().heightIn(min = 54.dp).novaControlBackground(16.dp).clip(RoundedCornerShape(16.dp))
        .novaRowPress(onClick = onClick).then(if (identifier != null) Modifier.testTag(identifier) else Modifier)
        .padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaIcon(symbol, 22.dp, Modifier.width(26.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText(title, style = NovaTypeToken.buttonSm)
            if (subtitle != null) NovaText(subtitle, style = NovaTypeToken.metaQuiet)
        }
        NovaIcon("chevron.right", 14.dp)
    }
}

/** Label and compact control share a row; accessibility text sizes stack them. */
@Composable
fun NovaFormValueRow(label: String, symbol: String = "calendar", modifier: Modifier = Modifier,
                     content: @Composable () -> Unit) {
    val stacked = novaFontScaleIsAccessibility()
    val caption = @Composable {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(symbol, 17.dp)
            NovaText(label, style = NovaTypeToken.label)
        }
    }
    val base = modifier.fillMaxWidth().heightIn(min = 48.dp).novaControlBackground(14.dp).padding(12.dp)
    if (stacked) Column(base, verticalArrangement = Arrangement.spacedBy(8.dp)) { caption(); content() }
    else Row(base, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.weight(1f)) { caption() }
        content()
    }
}

/** A NOVA-styled notice with one acknowledgement (replaces the platform alert, which ignores the palette). */
@Composable
fun NovaNoticeDialog(message: String?, title: String = "İSGADA", onDismiss: () -> Unit) {
    NovaPopup(message != null, onDismiss, identifier = "nova.notice.dialog") {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            NovaPopupHeading(title, symbol = "info.circle")
            NovaText(message.orEmpty())
            NovaButton("Tamam", onDismiss)
        }
    }
}

/** A short list of choices in the NOVA popup (the iOS confirmation dialog counterpart). */
@Composable
fun NovaChoiceDialog(visible: Boolean, title: String, options: List<Triple<String, String, () -> Unit>>, onDismiss: () -> Unit) {
    NovaPopup(visible, onDismiss, identifier = "nova.choice.dialog") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading(title, symbol = "square.and.arrow.up")
            options.forEach { (label, symbol, action) -> NovaPopupOption(label, symbol) { onDismiss(); action() } }
        }
    }
}
