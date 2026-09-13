package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.sp
import java.util.Locale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.vectorResource
import com.riskdetectedan.core.designsystem.R
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.tooling.preview.Preview

/** Caller applies events to its LATEST state with apply(event, epoch); never assign a captured copy.
 * This shell is not installed in the live app and contains no Auth/network/billing service. */
@Composable
fun NovaExpertShell(state: NovaNavigationState, userName: String, modifier: Modifier = Modifier,
                    hasUnread: Boolean = false, onEvent: (NovaNavigationEvent, String) -> Unit,
                    notices: List<NovaNotice> = emptyList(), connectionLabel: String = "Bağlantı bilgisi yok",
                    onNoticeAction: ((NovaNoticeAction, String) -> Unit)? = null,
                    onLogout: ((String) -> Unit)? = null,
                    content: @Composable (NovaDestination) -> Unit) {
    val send: (NovaNavigationEvent) -> Unit = { onEvent(it, state.epoch) }
    BackHandler(enabled = state.canGoBack && state.overlay == null) { send(NovaNavigationEvent.Back) }
    key(state.epoch) {
        val saved = rememberSaveableStateHolder()
        LaunchedEffect(state.available) {
            NovaDestination.entries.filterNot(state::canOpen).forEach { saved.removeState(it.name) }
        }
        Column(modifier.fillMaxSize().background(NovaColorToken.canvas.color())
            .blur(if (state.overlay == NovaOverlay.quickAdd) 7.dp else 0.dp).safeDrawingPadding()) {
            NovaShellTopBar(state.current, userName, hasUnread, !state.paths[state.selected].isNullOrEmpty(), state.canOpen(NovaDestination.notifications), send)
            Box(Modifier.weight(1f).fillMaxWidth()) {
                saved.SaveableStateProvider(state.current.name) { NovaPageSurface { content(state.current) } }
            }
            NovaShellTabBar(state.selected, state::canOpen, send,
                Modifier.padding(horizontal = 14.dp).padding(top = 8.dp, bottom = 16.dp))
        }
        state.overlay?.let { panel ->
            Dialog(onDismissRequest = { send(NovaNavigationEvent.Dismiss) },
                properties = DialogProperties(usePlatformDefaultWidth = false)) {
                val window = (LocalView.current.parent as? DialogWindowProvider)?.window
                val dim = if (panel == NovaOverlay.quickAdd) 0.34f else NovaColorToken.scrim.color().alpha
                DisposableEffect(window, dim) {
                    val previous = window?.attributes?.dimAmount
                    window?.setDimAmount(dim)
                    onDispose { if (previous != null) window.setDimAmount(previous) }
                }
                NovaShellPanel(panel, state.current, userName, state::canOpen, send, notices, connectionLabel,
                    onNoticeAction?.let { callback -> { action -> callback(action, state.epoch) } },
                    onLogout?.let { callback -> { callback(state.epoch) } })
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
            NovaText("NOVA", style = NovaTypeToken.brand)
            NovaText("Saha denetim asistanı", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
        }
        Box {
            NovaShellIcon(Icons.Outlined.Notifications, if (hasUnread) "Bildirimler, yeni bildirim var" else "Bildirimler", "nova.notifications", notificationsAvailable) {
                send(NovaNavigationEvent.Open(NovaOverlay.notifications))
            }
            if (hasUnread) Box(Modifier.align(Alignment.TopEnd).padding(7.dp).size(8.dp)
                .background(NovaColorToken.statusDangerDot.color(), CircleShape))
        }
        Box(Modifier.size(48.dp).background(Color(0xFF27272A), RoundedCornerShape(14.dp))
            .clickable(role = Role.Button) { send(NovaNavigationEvent.Select(NovaTab.profile)) }
            .semantics(mergeDescendants = true) { contentDescription = "Hesabım" }.testTag("nova.profile"), contentAlignment = Alignment.Center) {
            if (expanded) NovaGlyph(Icons.Outlined.Person, null, tint = Color.White)
            else NovaText(novaInitials(userName), style = NovaTypeToken.label, color = Color.White)
        }
    }
    if (expanded) {
        Spacer(Modifier.height(8.dp))
        NovaText("NOVA", style = NovaTypeToken.brand)
        NovaText("Saha denetim asistanı", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
    }
    }
}

@Composable
private fun NovaShellIcon(icon: ImageVector, label: String, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(Modifier.requiredSize(48.dp)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick).semantics { contentDescription = label }.testTag(tag),
        contentAlignment = Alignment.Center) {
        NovaGlyph(icon, null, Modifier.size(19.dp), tint = if (tag == "nova.notifications") NovaColorToken.accentInk.color() else NovaColorToken.text.color())
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
        color = NovaColorToken.surface.color(), shadowElevation = 1.dp,
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
            NovaGlyph(if (tab == null) Icons.Outlined.Add else tab.root.icon(), null, Modifier.size(if (tab == null) 21.dp else 19.dp),
                tint = if (tab == null) Color.White else NovaColorToken.text.color().copy(alpha = if (enabled) (if (active) 1f else .5f) else .4f))
        }
        NovaText(tab?.title ?: "Ekle", style = NovaTypeToken.tab,
            color = if (tab == null) NovaColorToken.accent.color() else NovaColorToken.text.color().copy(alpha = if (enabled) (if (active) 1f else .5f) else .4f))
    }
}

data class NovaNotice(val id: String, val title: String, val detail: String, val count: Int,
                      val icon: ImageVector, val tone: NovaColorToken, val unread: Boolean = true,
                      val destination: NovaDestination = NovaDestination.notifications)
enum class NovaNoticeAction { ReadAll, Clear }
internal fun novaInitials(name: String) = name.trim().split(Regex("\\s+")).take(2)
    .mapNotNull { it.firstOrNull()?.toString() }.joinToString("").uppercase(Locale.forLanguageTag("tr-TR"))

/** Shared compact popup style. Scrolls only when intrinsic content exceeds available height. */
@Composable
fun NovaPopupSurface(modifier: Modifier = Modifier, isPopover: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier, shape = RoundedCornerShape(if (isPopover) 26.dp else 30.dp), color = NovaColorToken.canvasSheet.color(),
        border = if (isPopover) null else androidx.compose.foundation.BorderStroke(1.dp, NovaColorToken.glassBorder.color())) {
        Column(Modifier.padding(if (isPopover) 14.dp else 16.dp).verticalScroll(rememberScrollState()).testTag("nova.panel.scroll"), content = content)
    }
}

@Composable
internal fun NovaShellPanel(panel: NovaOverlay, selected: NovaDestination, userName: String,
                             canOpen: (NovaDestination) -> Boolean, send: (NovaNavigationEvent) -> Unit,
                             notices: List<NovaNotice> = emptyList(), connectionLabel: String = "Bağlantı bilgisi yok",
                             onNoticeAction: ((NovaNoticeAction) -> Unit)? = null, onLogout: (() -> Unit)? = null) {
    BoxWithConstraints(Modifier.fillMaxSize(),
        contentAlignment = if (panel == NovaOverlay.drawer) Alignment.CenterStart else if (panel == NovaOverlay.notifications) Alignment.TopCenter else Alignment.Center) {
        Box(Modifier.fillMaxSize().clickable { send(NovaNavigationEvent.Dismiss) }.testTag("nova.panel.scrim"))
        if (panel == NovaOverlay.drawer) {
            val width = (if (LocalDensity.current.fontScale >= 1.5f) 360.dp else 290.dp).coerceAtMost(maxWidth - 48.dp)
            Surface(Modifier.width(width).fillMaxHeight(), color = NovaColorToken.canvasSheet.color()) {
                Column(Modifier.safeDrawingPadding().padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.size(48.dp).background(Color(0xFF27272A), RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
                            NovaText(novaInitials(userName), style = NovaTypeToken.cardTitle, color = Color.White)
                        }
                        Column(Modifier.weight(1f)) {
                            NovaText(userName, style = NovaTypeToken.sectionTitle)
                            NovaText("İSG Uzmanı", style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color())
                        }
                        NovaShellIcon(Icons.Outlined.Close, "Kapat", "nova.panel.close") { send(NovaNavigationEvent.Dismiss) }
                    }
                    NovaText(connectionLabel, Modifier.padding(top = 18.dp, bottom = 14.dp), NovaTypeToken.meta, NovaColorToken.statusSuccessInk.color())
                    HorizontalDivider(color = NovaColorToken.hairline.color())
                    Column(Modifier.weight(1f).padding(top = 12.dp).verticalScroll(rememberScrollState()).testTag("nova.panel.scroll")) {
                        NovaDestination.drawer.forEach { destination ->
                            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).alpha(if (canOpen(destination)) 1f else .4f)
                                .clickable(enabled = canOpen(destination), role = Role.Button) { send(NovaNavigationEvent.Navigate(destination)) }
                                .testTag("nova.destination.${destination.name}").padding(horizontal = 8.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                NovaGlyph(if (destination == NovaDestination.training) Icons.Outlined.Description else destination.icon(), null, Modifier.size(18.dp), tint = NovaColorToken.textTertiary.color())
                                NovaSizeText(destination.title, 14f, color = NovaColorToken.textSecondary.color())
                            }
                        }
                    }
                    Row(Modifier.fillMaxWidth().padding(top = 10.dp).heightIn(min = 48.dp)
                        .background(NovaColorToken.surfaceMuted.color(), CircleShape).clickable(enabled = onLogout != null, role = Role.Button) { onLogout?.invoke() }
                        .testTag("nova.logout"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                        NovaGlyph(Icons.AutoMirrored.Outlined.Logout, null, Modifier.size(20.dp), tint = NovaColorToken.textSecondary.color())
                        Spacer(Modifier.width(8.dp))
                        NovaText("Çıkış yap", style = NovaTypeToken.button, color = NovaColorToken.textSecondary.color())
                    }
                }
            }
        } else {
            NovaPopupSurface(Modifier.safeDrawingPadding().padding(horizontal = if (panel == NovaOverlay.notifications) 16.dp else 14.dp)
                .padding(top = if (panel == NovaOverlay.notifications) 56.dp else 12.dp, bottom = 12.dp)
                .widthIn(max = 440.dp).fillMaxWidth().heightIn(max = maxHeight - 24.dp), isPopover = panel == NovaOverlay.notifications) {
                if (panel == NovaOverlay.quickAdd) {
                    NovaText("Ne eklemek istiyorsun?", Modifier.padding(horizontal = 4.dp).padding(bottom = 12.dp), NovaTypeToken.sectionTitle)
                    NovaDestination.quickAdd.forEach { destination ->
                        Row(Modifier.padding(bottom = 8.dp).fillMaxWidth().heightIn(min = 64.dp)
                            .background(NovaColorToken.surface.color(), RoundedCornerShape(20.dp))
                            .alpha(if (canOpen(destination)) 1f else .4f)
                            .clickable(enabled = canOpen(destination), role = Role.Button) { send(NovaNavigationEvent.Navigate(destination)) }
                            .testTag("nova.destination.${destination.name}").padding(horizontal = 14.dp, vertical = 13.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaGlyph(destination.quickIcon(), null, Modifier.size(38.dp).padding(8.dp), tint = destination.quickTone().color())
                            Column(Modifier.weight(1f)) {
                                NovaSizeText(if (destination == NovaDestination.newFinding) "Uygunsuzluk Ekle" else destination.title, 15f)
                                NovaText(destination.quickHint(), Modifier.padding(top = 2.dp), NovaTypeToken.meta, NovaColorToken.textMuted.color())
                            }
                            NovaGlyph(Icons.Outlined.ChevronRight, null, Modifier.size(14.dp), tint = NovaColorToken.borderStrong.color())
                        }
                    }
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).background(NovaColorToken.surfaceMuted.color(), CircleShape)
                        .clickable(role = Role.Button) { send(NovaNavigationEvent.Dismiss) }.testTag("nova.panel.close"),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                        NovaGlyph(Icons.Outlined.ChevronLeft, null, tint = NovaColorToken.textSecondary.color())
                        NovaText("Vazgeç", style = NovaTypeToken.button, color = NovaColorToken.textSecondary.color())
                    }
                } else {
                    Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.CenterStart) {
                        NovaText("Bildirimler", style = NovaTypeToken.sectionTitle)
                        Box(Modifier.align(Alignment.CenterEnd)) {
                            NovaShellIcon(Icons.Outlined.Close, "Kapat", "nova.panel.close") { send(NovaNavigationEvent.Dismiss) }
                        }
                    }
                    // TextButton expands its visual 32dp row to a 48dp accessibility target.
                    // Reserve that halo so it cannot clip the close control's hit region.
                    Spacer(Modifier.height(8.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = { onNoticeAction?.invoke(NovaNoticeAction.ReadAll) }, enabled = onNoticeAction != null && notices.isNotEmpty(), modifier = Modifier.height(32.dp).testTag("nova.notices.read")) {
                            NovaText("Tümünü oku", style = NovaTypeToken.meta, color = NovaColorToken.statusSuccessInk.color())
                        }
                        Box(Modifier.width(1.dp).height(14.dp).background(NovaColorToken.hairline.color()))
                        TextButton(onClick = { onNoticeAction?.invoke(NovaNoticeAction.Clear) }, enabled = onNoticeAction != null && notices.isNotEmpty(), modifier = Modifier.height(32.dp).testTag("nova.notices.clear")) {
                            NovaText("Bildirimleri sil", style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color())
                        }
                    }
                    if (notices.isEmpty()) NovaText("Yeni bildirim yok", Modifier.padding(16.dp), color = NovaColorToken.textMuted.color())
                    notices.forEach { notice ->
                        Row(Modifier.padding(bottom = 7.dp).fillMaxWidth().background(NovaColorToken.surface.color(), RoundedCornerShape(20.dp))
                            .clickable(enabled = canOpen(notice.destination), role = Role.Button) { send(NovaNavigationEvent.Navigate(notice.destination)) }
                            .testTag("nova.notice.${notice.id}").padding(horizontal = 12.dp, vertical = 11.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
                                NovaGlyph(notice.icon, null, Modifier.size(20.dp), tint = notice.tone.color())
                                if (notice.unread) Box(Modifier.align(Alignment.TopEnd).size(5.dp).background(NovaColorToken.statusDangerDot.color(), CircleShape))
                            }
                            Column(Modifier.weight(1f)) {
                                Row {
                                    NovaSizeText(notice.title, 13f, androidx.compose.ui.text.font.FontWeight.Bold, modifier = Modifier.weight(1f))
                                    NovaText(notice.count.toString(), style = NovaTypeToken.label, color = notice.tone.color())
                                }
                                NovaSizeText(notice.detail, 11f, androidx.compose.ui.text.font.FontWeight.Normal, NovaColorToken.textMuted.color(), Modifier.padding(top = 3.dp))
                            }
                        }
                    }
                    TextButton(onClick = { send(NovaNavigationEvent.Navigate(NovaDestination.notifications)) },
                        enabled = canOpen(NovaDestination.notifications), modifier = Modifier.height(32.dp).testTag("nova.notices.center")) {
                        NovaText("Bildirim merkezine git", style = NovaTypeToken.meta, color = NovaColorToken.statusSuccessInk.color())
                        NovaGlyph(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.size(14.dp), tint = NovaColorToken.statusSuccessInk.color())
                    }
                }
            }
        }
    }
}

private fun NovaDestination.quickHint() = when (this) {
    NovaDestination.newFinding -> "Bulgu, fotoğraf ve öncelik"
    NovaDestination.newDocument -> "Rapor, form veya belge yükle"
    NovaDestination.newVisit -> "Yeni saha ziyareti planla"
    NovaDestination.newTraining -> "Firma personeline eğitim kaydı oluştur"
    else -> ""
}
private fun NovaDestination.quickIcon() = when (this) {
    NovaDestination.newFinding -> Icons.Outlined.WarningAmber
    NovaDestination.newDocument -> Icons.Outlined.Description
    NovaDestination.newVisit -> Icons.Outlined.Place
    NovaDestination.newTraining -> Icons.Outlined.ThumbUp
    else -> icon()
}
private fun NovaDestination.quickTone() = when (this) {
    NovaDestination.newDocument -> NovaColorToken.statusInfoDot
    NovaDestination.newVisit -> NovaColorToken.statusWarningDot
    else -> NovaColorToken.statusSuccessDot
}

/** Page title reuses the destination glyph; never adds an icon background tile. */
@Composable
fun NovaPageTitle(destination: NovaDestination, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaGlyph(destination.icon(), null, Modifier.size(22.dp), tint = NovaColorToken.accent.color())
        NovaText(destination.title, style = NovaTypeToken.screenTitle)
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

/** Exact OSGB source vectors, converted without changing path coordinates or stroke widths. */
@Composable
fun NovaGlyph(imageVector: ImageVector, contentDescription: String?, modifier: Modifier = Modifier, tint: Color = NovaColorToken.text.color()) {
    val source = when (imageVector.name.substringAfterLast('.')) {
        "Home" -> R.drawable.nova_home
        "List" -> R.drawable.nova_list
        "Business" -> R.drawable.nova_firm
        "Place" -> R.drawable.nova_visit
        "Notifications" -> R.drawable.nova_bell
        "Person" -> R.drawable.nova_who
        "PhotoCamera" -> R.drawable.nova_camera_large
        "WarningAmber" -> R.drawable.nova_open_triangle
        "Warning" -> R.drawable.nova_risk
        "Description", "NoteAdd" -> R.drawable.nova_doc
        "History", "Folder", "Inventory2" -> R.drawable.nova_doc_download
        "ThumbUp", "School" -> R.drawable.nova_award
        "BarChart", "Assessment" -> R.drawable.nova_chart
        "Search" -> R.drawable.nova_search
        "BookmarkBorder" -> R.drawable.nova_bookmark
        "AccessTime" -> R.drawable.nova_clock
        "AutoAwesome" -> R.drawable.nova_star_filled
        "ChevronRight" -> R.drawable.nova_chevron_right
        "ChevronLeft", "ArrowBack" -> R.drawable.nova_back
        "ArrowForward" -> R.drawable.nova_arrow_right
        else -> null
    }
    Icon(if (source == null) imageVector else ImageVector.vectorResource(source), contentDescription, modifier, tint)
}
