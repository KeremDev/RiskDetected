package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.tooling.preview.Preview

/** Caller applies events to its LATEST state with apply(event, epoch); never assign a captured copy.
 * This shell is not installed in the live app and contains no Auth/network/billing service. */
@Composable
fun NovaExpertShell(state: NovaNavigationState, userName: String, modifier: Modifier = Modifier,
                    hasUnread: Boolean = false, onEvent: (NovaNavigationEvent, String) -> Unit,
                    content: @Composable (NovaDestination) -> Unit) {
    val send: (NovaNavigationEvent) -> Unit = { onEvent(it, state.epoch) }
    BackHandler(enabled = state.canGoBack && state.overlay == null) { send(NovaNavigationEvent.Back) }
    key(state.epoch) {
        val saved = rememberSaveableStateHolder()
        LaunchedEffect(state.available) {
            NovaDestination.entries.filterNot(state::canOpen).forEach { saved.removeState(it.name) }
        }
        Column(modifier.fillMaxSize().background(NovaColorToken.canvas.color()).safeDrawingPadding()) {
            NovaShellTopBar(state.current, userName, hasUnread, !state.paths[state.selected].isNullOrEmpty(), state.canOpen(NovaDestination.notifications), send)
            Box(Modifier.weight(1f).fillMaxWidth()) {
                saved.SaveableStateProvider(state.current.name) { content(state.current) }
            }
            NovaShellTabBar(state.selected, state::canOpen, send,
                Modifier.padding(horizontal = 14.dp).padding(top = 8.dp, bottom = 16.dp))
        }
        state.overlay?.let { panel ->
            Dialog(onDismissRequest = { send(NovaNavigationEvent.Dismiss) },
                properties = DialogProperties(usePlatformDefaultWidth = false)) {
                NovaShellPanel(panel, state.current, userName, state::canOpen, send)
            }
        }
    }
}

@Composable
internal fun NovaShellTopBar(current: NovaDestination, userName: String, hasUnread: Boolean,
                              canGoBack: Boolean, notificationsAvailable: Boolean, send: (NovaNavigationEvent) -> Unit) {
    val expanded = LocalDensity.current.fontScale >= 1.5f
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Row(Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaShellIcon(if (canGoBack) Icons.AutoMirrored.Outlined.ArrowBack else Icons.Outlined.Menu,
            if (canGoBack) "Geri" else "Menüyü aç", if (canGoBack) "nova.back" else "nova.menu") {
            send(if (canGoBack) NovaNavigationEvent.Back else NovaNavigationEvent.Open(NovaOverlay.drawer))
        }
        if (expanded) Spacer(Modifier.weight(1f)) else Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            NovaText("İSG Adası", style = NovaTypeToken.brand)
            NovaText(current.title, style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
        }
        Box {
            NovaShellIcon(Icons.Outlined.Notifications, if (hasUnread) "Bildirimler, yeni bildirim var" else "Bildirimler", "nova.notifications", notificationsAvailable) {
                send(NovaNavigationEvent.Navigate(NovaDestination.notifications))
            }
            if (hasUnread) Box(Modifier.align(Alignment.TopEnd).padding(7.dp).size(8.dp)
                .background(NovaColorToken.statusDangerDot.color(), CircleShape))
        }
        Box(Modifier.size(48.dp).background(Color(0xFF27272A), RoundedCornerShape(14.dp))
            .clickable(role = Role.Button) { send(NovaNavigationEvent.Select(NovaTab.profile)) }
            .semantics(mergeDescendants = true) { contentDescription = "Hesabım" }.testTag("nova.profile"), contentAlignment = Alignment.Center) {
            if (expanded) Icon(Icons.Outlined.Person, null, tint = Color.White)
            else NovaText(userName.take(2).uppercase(), style = NovaTypeToken.label, color = Color.White)
        }
    }
    if (expanded) {
        Spacer(Modifier.height(8.dp))
        NovaText("İSG Adası", style = NovaTypeToken.brand)
        NovaText(current.title, style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
    }
    }
}

@Composable
private fun NovaShellIcon(icon: ImageVector, label: String, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(Modifier.size(48.dp).background(NovaColorToken.surface.color(), RoundedCornerShape(14.dp))
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick).semantics { contentDescription = label }.testTag(tag),
        contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(17.dp), tint = NovaColorToken.text.color())
    }
}

@Composable
internal fun NovaShellTabBar(selected: NovaTab, canOpen: (NovaDestination) -> Boolean,
                              send: (NovaNavigationEvent) -> Unit, modifier: Modifier = Modifier) {
    val expanded = LocalDensity.current.fontScale >= 1.5f
    val slots: List<NovaTab?> = listOf(NovaTab.home, NovaTab.findings, null, NovaTab.companies, NovaTab.profile)
    val listState = rememberLazyListState()
    LaunchedEffect(selected, expanded) { if (expanded) listState.scrollToItem(slots.indexOf(selected)) }
    Surface(modifier.fillMaxWidth().heightIn(min = 66.dp), shape = RoundedCornerShape(34.dp),
        color = NovaColorToken.surface.color(), shadowElevation = 16.dp,
        border = androidx.compose.foundation.BorderStroke(1.dp, NovaColorToken.glassBorder.color())) {
        if (expanded) {
            LazyRow(state = listState, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                modifier = Modifier.testTag("nova.tabs.scroll")) {
                items(slots.size, key = { slots[it]?.name ?: "add" }) { index ->
                    NovaShellTabItem(slots[index], selected, canOpen, send, Modifier.widthIn(min = 96.dp).padding(horizontal = 12.dp))
                }
            }
        } else {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.Top) {
                slots.forEach { tab -> NovaShellTabItem(tab, selected, canOpen, send, Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun NovaShellTabItem(tab: NovaTab?, selected: NovaTab, canOpen: (NovaDestination) -> Boolean,
                             send: (NovaNavigationEvent) -> Unit, modifier: Modifier) {
    val active = tab == selected
    val enabled = tab == null || canOpen(tab.root)
    Column(modifier.heightIn(min = 52.dp)
        .clickable(enabled = enabled, role = if (tab == null) Role.Button else Role.Tab) {
            send(if (tab == null) NovaNavigationEvent.Open(NovaOverlay.quickAdd) else NovaNavigationEvent.Select(tab))
        }.semantics(mergeDescendants = true) { if (tab != null) this.selected = active }
        .testTag(if (tab == null) "nova.add" else "nova.tab.${tab.name}"),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(42.dp).then(if (tab == null) Modifier.background(NovaColorToken.accent.color(), CircleShape) else Modifier),
            contentAlignment = Alignment.Center) {
            Icon(if (tab == null) Icons.Outlined.Add else tab.root.icon(), null, Modifier.size(if (tab == null) 21.dp else 19.dp),
                tint = if (tab == null) Color(0xFF111111) else NovaColorToken.text.color().copy(alpha = if (enabled) (if (active) 1f else .7f) else .4f))
        }
        NovaText(tab?.title ?: "Ekle", style = NovaTypeToken.tab,
            color = NovaColorToken.text.color().copy(alpha = if (enabled) 1f else .4f))
    }
}

@Composable
internal fun NovaShellPanel(panel: NovaOverlay, selected: NovaDestination, userName: String,
                             canOpen: (NovaDestination) -> Boolean, send: (NovaNavigationEvent) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding(),
        contentAlignment = if (panel == NovaOverlay.drawer) Alignment.CenterStart else Alignment.Center) {
        val width = (maxWidth * if (panel == NovaOverlay.drawer) .9f else .92f).coerceAtMost(if (panel == NovaOverlay.drawer) 384.dp else 520.dp)
        Surface(Modifier.padding(start = if (panel == NovaOverlay.drawer) 8.dp else 0.dp).width(width).heightIn(max = maxHeight - 24.dp),
            shape = RoundedCornerShape(28.dp), color = NovaColorToken.canvasSheet.color()) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NovaText(if (panel == NovaOverlay.drawer) "İSG Adası" else "Hızlı İşlem", Modifier.weight(1f), NovaTypeToken.sheetTitle)
                    NovaShellIcon(Icons.Outlined.Close, "Kapat", "nova.panel.close") { send(NovaNavigationEvent.Dismiss) }
                }
                if (panel == NovaOverlay.drawer) NovaText(userName, style = NovaTypeToken.bodyStrong)
                Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    (if (panel == NovaOverlay.drawer) NovaDestination.drawer else NovaDestination.quickAdd).forEach { destination ->
                        val enabled = canOpen(destination)
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .background(if (selected == destination) NovaColorToken.accentSoft.color() else NovaColorToken.surface.color(), RoundedCornerShape(14.dp))
                            .clickable(enabled = enabled, role = Role.Button) { send(NovaNavigationEvent.Navigate(destination)) }
                            .testTag("nova.destination.${destination.name}").padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(destination.icon(), null, Modifier.size(24.dp), tint = NovaColorToken.text.color())
                            Column(Modifier.weight(1f)) {
                                NovaText(destination.title, style = NovaTypeToken.bodyStrong)
                                if (!enabled) NovaText("Henüz kullanıma açık değil", style = NovaTypeToken.metaQuiet)
                            }
                            Icon(Icons.Outlined.ChevronRight, null, Modifier.size(16.dp), tint = NovaColorToken.text.color())
                        }
                    }
                }
            }
        }
    }
}

private fun NovaDestination.icon(): ImageVector = when (this) {
    NovaDestination.home -> Icons.Outlined.Home
    NovaDestination.newFinding -> Icons.Outlined.PhotoCamera
    NovaDestination.findings -> Icons.AutoMirrored.Outlined.List
    NovaDestination.companies -> Icons.Outlined.Business
    NovaDestination.memory -> Icons.Outlined.History
    NovaDestination.documentChecklist -> Icons.Outlined.Description
    NovaDestination.documents -> Icons.Outlined.Folder
    NovaDestination.visits -> Icons.Outlined.Place
    NovaDestination.statistics -> Icons.Outlined.BarChart
    NovaDestination.training -> Icons.Outlined.School
    NovaDestination.reports -> Icons.Outlined.Assessment
    NovaDestination.reportArchive -> Icons.Outlined.Inventory2
    NovaDestination.notifications -> Icons.Outlined.Notifications
    NovaDestination.profile -> Icons.Outlined.Person
    NovaDestination.newDocument -> Icons.AutoMirrored.Outlined.NoteAdd
    NovaDestination.newVisit -> Icons.Outlined.Event
    NovaDestination.newTraining -> Icons.Outlined.School
}

@Composable
internal fun NovaExpertShellDemo() {
    var state by remember { mutableStateOf(NovaNavigationState("preview-only", NovaDestination.entries.toSet())) }
    NovaExpertShell(state, "Örnek Uzman", onEvent = { event, epoch -> state = state.apply(event, epoch) }) { destination ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
            NovaCard(Modifier.fillMaxWidth()) {
                NovaText(destination.title, style = NovaTypeToken.screenTitle)
                NovaText("Gezinme önizlemesi. Canlı veriye bağlı değil; bu modülün iş akışı henüz bağlanmadı.")
            }
        }
    }
}
@Preview @Composable private fun NovaExpertShellLightPreview() = NovaTheme(false) { NovaExpertShellDemo() }
@Preview @Composable private fun NovaExpertShellDarkPreview() = NovaTheme(true) { NovaExpertShellDemo() }
