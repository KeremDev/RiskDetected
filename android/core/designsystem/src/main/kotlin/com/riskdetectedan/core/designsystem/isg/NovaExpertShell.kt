package com.riskdetectedan.core.designsystem.isg

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.R

/** Standalone destinations keep the same functioning header as shell destinations. */
data class NovaHeaderContext(val current: NovaDestination, val userName: String, val unreadCount: Int,
                             val hasUnread: Boolean, val pendingActionCount: Int?, val notificationsAvailable: Boolean,
                             val pageSummary: NovaHeaderSummary?, val setPageSummary: (NovaHeaderSummary?) -> Unit,
                             val pageBackAction: (() -> Unit)?, val setPageBackAction: ((() -> Unit)?) -> Unit,
                             val send: (NovaNavigationEvent) -> Unit)

data class NovaHeaderSummary(val title: String, val recordCount: Int, val upcomingCount: Int)

val LocalNovaHeaderContext = staticCompositionLocalOf<NovaHeaderContext?> { null }

@Composable
fun NovaStandaloneHeader() {
    val context = LocalNovaHeaderContext.current
    if (context != null) NovaShellTopBar(context.current, context.userName, context.hasUnread, context.unreadCount, context.pendingActionCount,
        context.notificationsAvailable, context.send, context.pageSummary, context.pageBackAction)
    else NovaText("İSGADA", Modifier.fillMaxWidth().padding(vertical = 8.dp), NovaTypeToken.brand, textAlign = TextAlign.Center)
}

/** One line in the bell. The owner computes every field; `id` is the key it marks the notice by. */
data class NovaNotice(val id: String, val title: String, val detail: String, val badge: String,
                      val symbol: String, val tone: NovaColorToken, val unread: Boolean = true,
                      val dismissed: Boolean = false, val destination: NovaDestination = NovaDestination.notifications)

/** Compact, actionable summary cards at the top of the drawer. */
data class NovaMenuStat(val id: String, val title: String, val value: String, val symbol: String,
                        val destination: NovaDestination)

/** The next best action, supplied from the account's current data. */
data class NovaMenuNextAction(val title: String, val symbol: String, val destination: NovaDestination,
                              val completed: Int, val total: Int,
                              /** Set when the action comes from a "Senin İçin" card: the card opens its own target. */
                              val onSelect: (() -> Unit)? = null) {
    val progress: Float get() = if (total <= 0) 0f else (completed.toFloat() / total).coerceIn(0f, 1f)
}

/** Everything the shell needs from its owner besides navigation state. */
data class NovaShellActions(
    val onReadNotice: ((String) -> Unit)? = null,
    val onOpenNotice: ((String) -> Unit)? = null,
    val onDismissNotice: ((String) -> Unit)? = null,
    val onRestoreNotice: ((String) -> Unit)? = null,
    val onReadAll: (() -> Unit)? = null,
    val onClearNotifications: (() -> Unit)? = null,
    val onCompanyCreate: (() -> Unit)? = null,
    val onExpertCreate: (() -> Unit)? = null,
    val onAssignmentOpen: (() -> Unit)? = null,
    val onInvite: (() -> Unit)? = null,
    val onDestination: ((NovaDestination) -> Unit)? = null,
    val onLogout: (() -> Unit)? = null,
)

/**
 * The expert shell (iOS `NovaExpertShell`). The owner supplies scoped state and
 * real destination content; this layer has no Auth, network or billing.
 * Callers apply events to their LATEST state with `apply(event, epoch)`.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun NovaExpertShell(state: NovaNavigationState, userName: String, onEvent: (NovaNavigationEvent, String) -> Unit,
                    modifier: Modifier = Modifier, notebookAvailable: Boolean = false,
                    profileAvatar: ImageBitmap? = null, menuRoleTitle: String = "İSG Uzmanı",
                    menuStats: List<NovaMenuStat> = emptyList(), menuNextAction: NovaMenuNextAction? = null,
                    hasUnread: Boolean = false, unreadCount: Int = 0, pendingActionCount: Int? = null, notices: List<NovaNotice> = emptyList(),
                    noticeNote: String = "", connectionLabel: String = "Bağlantı bilgisi yok",
                    isManager: Boolean = false, actions: NovaShellActions = NovaShellActions(),
                    content: @Composable (NovaDestination) -> Unit) {
    val epoch = state.epoch
    val send: (NovaNavigationEvent) -> Unit = { onEvent(it, epoch) }
    var pageSummary by remember { mutableStateOf<NovaHeaderSummary?>(null) }
    var pageBackAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    LaunchedEffect(state.current) {
        if (state.current != NovaDestination.riskAssessments) {
            pageSummary = null
            pageBackAction = null
        }
    }
    BackHandler(enabled = state.canGoBack) { send(NovaNavigationEvent.Back) }
    key(epoch) {
        val saved = rememberSaveableStateHolder()
        LaunchedEffect(state.available) {
            NovaDestination.entries.filterNot(state::canOpen).forEach { saved.removeState(it.name) }
        }
        val header = NovaHeaderContext(state.current, userName, unreadCount, hasUnread, pendingActionCount,
            state.canOpen(NovaDestination.notifications), pageSummary,
            { summary -> if (state.current == NovaDestination.riskAssessments) pageSummary = summary }, pageBackAction,
            { action -> if (state.current == NovaDestination.riskAssessments) pageBackAction = action }, send)
        val keyboardOpen = WindowInsets.isImeVisible
        CompositionLocalProvider(LocalNovaHeaderContext provides header) {
            Box(modifier.fillMaxSize().background(NovaColorToken.canvas.color())) {
                Box(Modifier.fillMaxSize()
                    .blur(if (state.overlay == NovaOverlay.quickAdd) NovaPopupStyle.sourceBlur else 0.dp)
                    .then(if (state.overlay != null) Modifier.clearAndSetSemantics {} else Modifier)) {
                    Column(Modifier.fillMaxSize().statusBarsPadding()) {
                        NovaShellTopBar(state.current, userName, hasUnread, unreadCount, pendingActionCount,
                            state.canOpen(NovaDestination.notifications), send, pageSummary, pageBackAction)
                        NovaShellContent(state, saved, content)
                    }
                    AnimatedVisibility(!keyboardOpen, Modifier.align(Alignment.BottomCenter),
                        enter = fadeIn(NovaMotion.easeOut()) + slideInVertically(NovaMotion.easeOut()) { it / 2 },
                        exit = fadeOut(NovaMotion.easeOut()) + slideOutVertically(NovaMotion.easeOut()) { it / 2 }) {
                        NovaShellTabBar(state.selected, state.current, state::canOpen, send, actions.onDestination,
                            Modifier.padding(horizontal = NovaDimensionToken.layoutTabBarInset.value.dp)
                                .navigationBarsPadding().padding(top = 8.dp, bottom = 10.dp))
                    }
                }
                NovaShellOverlay(state.overlay, state.current, state::canOpen, userName, profileAvatar, menuRoleTitle,
                    menuStats, menuNextAction, send, notices, connectionLabel, noticeNote, isManager, notebookAvailable, actions)
            }
        }
    }
}

/** Push/pop slides inside a tab, a short cross-fade between tabs. */
@Composable
private fun NovaShellContent(state: NovaNavigationState, saved: androidx.compose.runtime.saveable.SaveableStateHolder,
                             content: @Composable (NovaDestination) -> Unit) {
    val reduceMotion = rememberNovaReduceMotion()
    val depth = state.paths[state.selected]?.size ?: 0
    val target = Triple(state.selected, state.current, depth)
    AnimatedContent(target, Modifier.fillMaxSize(), transitionSpec = {
        val sameTab = initialState.first == targetState.first
        when {
            reduceMotion || !sameTab -> fadeIn(NovaMotion.easeOut(NovaMotion.Duration.popover)) togetherWith
                fadeOut(NovaMotion.easeOut(NovaMotion.Duration.popover))
            targetState.third >= initialState.third ->
                (slideInHorizontally(NovaMotion.drawer()) { it } + fadeIn(NovaMotion.drawer())) togetherWith
                    (slideOutHorizontally(NovaMotion.drawer()) { -it / 4 } + fadeOut(NovaMotion.drawer()))
            else -> (slideInHorizontally(NovaMotion.drawer()) { -it / 4 } + fadeIn(NovaMotion.drawer())) togetherWith
                (slideOutHorizontally(NovaMotion.drawer()) { it } + fadeOut(NovaMotion.drawer()))
        }
    }, label = "novaShellContent") { (_, destination, _) ->
        saved.SaveableStateProvider(destination.name) {
            NovaPageSurface {
                if (state.canOpen(destination)) content(destination)
                else NovaText("Bu bölüm henüz kullanıma açık değil.", Modifier.padding(20.dp))
            }
        }
    }
}

@Composable
fun NovaShellTopBar(current: NovaDestination, userName: String, hasUnread: Boolean, unreadCount: Int, pendingActionCount: Int?,
                    notificationsAvailable: Boolean, send: (NovaNavigationEvent) -> Unit,
                    pageSummary: NovaHeaderSummary? = null, pageBackAction: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = NovaDimensionToken.spaceScreenX.value.dp).padding(top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaShellIconButton("line.3.horizontal", "Menüyü aç", "nova.menu") { send(NovaNavigationEvent.Open(NovaOverlay.drawer)) }
        if (current == NovaDestination.riskAssessments && pageBackAction != null) {
            NovaShellIconButton("chevron.left", "Geri", "nova.risk.back", onClick = pageBackAction)
        }
        if (current == NovaDestination.home) {
            Column(Modifier.height(48.dp), verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)) {
                NovaText("Merhaba, ${userName.split(' ').firstOrNull()?.takeIf(String::isNotBlank) ?: "İSGADA"}",
                    style = NovaTypeToken.cardTitle, color = NovaColorToken.text.color(), maxLines = 1)
                NovaText(pendingActionCount?.let { if (it == 0) "Bekleyen işlem yok" else "$it işlem dikkat bekliyor" } ?: "İşlemler yükleniyor…",
                    style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color(), maxLines = 1)
            }
        } else if (current == NovaDestination.riskAssessments) {
            Column(Modifier.height(48.dp), verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
                NovaText(pageSummary?.title ?: NovaDestination.riskAssessments.title,
                    style = NovaTypeToken.cardTitle, color = NovaColorToken.text.color(), maxLines = 1)
                pageSummary?.let { summary ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        HeaderPageStat("circle.fill", summary.recordCount, "Kayıt")
                        HeaderPageStat("list.bullet", summary.upcomingCount, "Yaklaşan")
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Box {
            NovaShellIconButton("bell", if (hasUnread) "Bildirimler, yeni bildirim var" else "Bildirimler",
                "nova.notifications", notificationsAvailable) { send(NovaNavigationEvent.Open(NovaOverlay.notifications)) }
            val dot = NovaColorToken.statusDangerDot.color()
            if (unreadCount > 0) Box(Modifier.align(Alignment.TopEnd).padding(4.dp).heightIn(min = 16.dp).widthIn(min = 16.dp)
                .background(dot, CircleShape).padding(horizontal = 4.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
                NovaSizedText(if (unreadCount > 99) "99+" else unreadCount.toString(), 10f, FontWeight.Bold, Color.White)
            } else if (hasUnread) Box(Modifier.align(Alignment.TopEnd).padding(7.dp).size(8.dp).background(dot, CircleShape))
        }
        NovaShellIconButton("person.fill", "Hesabım", "nova.profile") { send(NovaNavigationEvent.Select(NovaTab.profile)) }
    }
}

@Composable
private fun HeaderPageStat(symbol: String, value: Int, label: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, if (symbol == "circle.fill") 6.dp else 9.dp, tint = NovaColorToken.text.color())
        NovaSizedText(value.toString(), 10f, FontWeight.Bold, NovaColorToken.text.color(), maxLines = 1)
        NovaSizedText(label, 10f, FontWeight.Normal, NovaColorToken.text.color(), maxLines = 1)
    }
}

@Composable
private fun NovaShellIconButton(symbol: String, label: String, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    // 44dp visual tile (iOS) inside Android's 48dp minimum touch target.
    Box(Modifier.size(48.dp).novaPress(enabled = enabled, onClick = onClick)
        .semantics { contentDescription = label }.testTag(tag), contentAlignment = Alignment.Center) {
        Box(Modifier.size(44.dp).shadow(5.dp, shape, ambientColor = Color.Black.copy(alpha = 0.06f), spotColor = Color.Black.copy(alpha = 0.06f))
            .clip(shape).background(Color.White, shape), contentAlignment = Alignment.Center) {
            NovaIcon(symbol, 19.dp, tint = Color.Black.copy(alpha = if (enabled) 1f else 0.4f))
        }
    }
}

@Composable
fun NovaShellTabBar(selected: NovaTab, current: NovaDestination, canOpen: (NovaDestination) -> Boolean,
                    send: (NovaNavigationEvent) -> Unit, onDestination: ((NovaDestination) -> Unit)? = null,
                    modifier: Modifier = Modifier) {
    val haptics = rememberNovaHaptics()
    Row(modifier.fillMaxWidth().height(62.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f).height(62.dp)
            .shadow(18.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.07f), spotColor = Color.Black.copy(alpha = 0.07f))
            .clip(CircleShape).background(NovaColorToken.surface.color().copy(alpha = 0.92f), CircleShape)
            .border(1.dp, Color.White.copy(alpha = 0.78f), CircleShape).padding(5.dp), contentAlignment = Alignment.Center) {
            NovaShellTabStrip(selected, canOpen, send, onDestination)
        }
        AnimatedVisibility(current != NovaDestination.analyses,
            enter = fadeIn(NovaMotion.easeOut()) + scaleIn(NovaMotion.easeOut(), 0.9f),
            exit = fadeOut(NovaMotion.easeOut()) + scaleOut(NovaMotion.easeOut(), 0.9f)) {
            Box(Modifier.size(62.dp).shadow(18.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.07f))
                .clip(CircleShape).background(Color(0xFF0B2F53), CircleShape)
                .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape)
                .novaPress(scale = 0.93f, pressedAlpha = 0.72f) {
                    haptics.impact()
                    send(NovaNavigationEvent.Open(NovaOverlay.quickAdd))
                }
                .semantics { contentDescription = "Ekle" }.testTag("nova.add"), contentAlignment = Alignment.Center) {
                NovaIcon("plus", 28.dp, tint = Color.White)
            }
        }
    }
}

@Composable
fun NovaShellTabStrip(selected: NovaTab, canOpen: (NovaDestination) -> Boolean, send: (NovaNavigationEvent) -> Unit,
                      onDestination: ((NovaDestination) -> Unit)? = null) {
    val haptics = rememberNovaHaptics()
    val reduceMotion = rememberNovaReduceMotion()
    val tabs = listOf(NovaTab.home, NovaTab.companies, NovaTab.findings, NovaTab.profile)
    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        // iOS sizes the selected capsule for a 402pt screen; narrow Android phones
        // give it only what is left after three 48dp targets.
        val gap = 2.dp
        val rest = 48.dp
        val selectedWidth = (maxWidth - rest * (tabs.size - 1) - gap * (tabs.size - 1)).coerceIn(rest, 116.dp)
        Row(horizontalArrangement = Arrangement.spacedBy(gap, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            tabs.forEach { tab ->
                val on = selected == tab
                val enabled = canOpen(tab.root)
                val width by animateDpAsState(if (on) selectedWidth else rest, NovaMotion.stopped(NovaMotion.momentum(), reduceMotion), label = "tabWidth")
                val fill by animateFloatAsState(if (on) 1f else 0f, NovaMotion.stopped(NovaMotion.momentum(), reduceMotion), label = "tabFill")
                Box(Modifier.width(width).height(48.dp).clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.82f * fill), CircleShape)
                    .border(0.8.dp, Color.White.copy(alpha = 0.86f * fill), CircleShape)
                    .novaPress(enabled = enabled, scale = 0.93f, pressedAlpha = 0.72f, role = Role.Tab) {
                        haptics.selection()
                        onDestination?.invoke(tab.root)
                        send(NovaNavigationEvent.Select(tab))
                    }
                    .alphaIf(!enabled, 0.3f)
                    .semantics { contentDescription = tab.title; this.selected = on }.testTag("nova.tab.${tab.name}"),
                    contentAlignment = Alignment.Center) {
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(horizontal = if (on) 12.dp else 0.dp)) {
                        NovaIcon(tabSymbol(tab), 22.dp, tint = Color.Black)
                        AnimatedVisibility(on && selectedWidth >= 110.dp,
                            enter = fadeIn(NovaMotion.easeOut(NovaMotion.Duration.popover)) + scaleIn(NovaMotion.easeOut(NovaMotion.Duration.popover), 0.92f),
                            exit = fadeOut(NovaMotion.easeOut(0.1))) {
                            NovaSizedText(tab.title, 12.5f, FontWeight.Bold, Color.Black, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

private fun tabSymbol(tab: NovaTab) = when (tab) {
    NovaTab.home -> "house"
    NovaTab.companies -> "building.2"
    NovaTab.findings -> "checklist"
    NovaTab.profile -> "person"
}

private fun Modifier.alphaIf(condition: Boolean, alpha: Float) = if (condition) this.graphicsAlpha(alpha) else this

@Composable
private fun NovaShellOverlay(panel: NovaOverlay?, selected: NovaDestination, canOpen: (NovaDestination) -> Boolean,
                             userName: String, avatar: ImageBitmap?, roleTitle: String, stats: List<NovaMenuStat>,
                             nextAction: NovaMenuNextAction?, send: (NovaNavigationEvent) -> Unit, notices: List<NovaNotice>,
                             connectionLabel: String, noticeNote: String, isManager: Boolean, notebookAvailable: Boolean,
                             actions: NovaShellActions) {
    val reduceMotion = rememberNovaReduceMotion()
    BackHandler(enabled = panel != null) { send(NovaNavigationEvent.Dismiss) }
    // Last non-null panel keeps drawing while it leaves.
    var shown by remember { mutableStateOf(panel) }
    if (panel != null) shown = panel
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(panel != null, enter = fadeIn(NovaMotion.easeOut()), exit = fadeOut(NovaMotion.easeOut(NovaMotion.Duration.popover))) {
            val scrim = if (shown == NovaOverlay.quickAdd) Color.Black.copy(alpha = NovaPopupStyle.dimOpacity) else NovaColorToken.scrim.color()
            Box(Modifier.fillMaxSize().background(scrim).clickable(remember { MutableInteractionSource() }, null) {
                send(NovaNavigationEvent.Dismiss)
            }.testTag("nova.panel.scrim"))
        }
        AnimatedVisibility(panel == NovaOverlay.drawer, Modifier.align(Alignment.CenterStart),
            enter = if (reduceMotion) fadeIn(NovaMotion.easeOut()) else slideInHorizontally(NovaMotion.drawer()) { -it },
            exit = if (reduceMotion) fadeOut(NovaMotion.easeOut()) else slideOutHorizontally(NovaMotion.drawer(0.24)) { -it }) {
            val width = if (novaFontScaleIsAccessibility()) 380.dp else 340.dp
            BoxWithConstraints {
                Box(Modifier.width(width.coerceAtMost(maxWidth - 24.dp)).fillMaxHeight()
                    .background(NovaColorToken.canvasSheet.color()).semantics { isTraversalGroup = true; paneTitle = "Menü" }) {
                    NovaDrawer(selected, canOpen, userName, avatar, roleTitle, stats, nextAction, send, isManager,
                        notebookAvailable, actions)
                }
            }
        }
        AnimatedVisibility(panel == NovaOverlay.quickAdd, Modifier.align(Alignment.Center),
            enter = fadeIn(NovaMotion.easeOut(0.24)) + if (reduceMotion) fadeIn(NovaMotion.easeOut(0.0)) else scaleIn(NovaMotion.easeOut(0.24), NovaPopupTransition.enterScale),
            exit = fadeOut(NovaMotion.easeOut(0.16)) + if (reduceMotion) fadeOut(NovaMotion.easeOut(0.0)) else scaleOut(NovaMotion.easeOut(0.16), NovaPopupTransition.enterScale)) {
            NovaPanelSurface(Modifier.safeDrawingPadding().padding(horizontal = 14.dp).widthIn(max = 440.dp)) {
                NovaQuickAdd(canOpen, send, isManager, notebookAvailable, actions)
            }
        }
        AnimatedVisibility(panel == NovaOverlay.notifications, Modifier.align(Alignment.TopCenter),
            enter = fadeIn(NovaMotion.easeOut(NovaMotion.Duration.popover)) + if (reduceMotion) fadeIn(NovaMotion.easeOut(0.0)) else scaleIn(NovaMotion.easeOut(NovaMotion.Duration.popover), 0.96f, androidx.compose.ui.graphics.TransformOrigin(0.85f, 0f)),
            exit = fadeOut(NovaMotion.easeOut(0.14)) + if (reduceMotion) fadeOut(NovaMotion.easeOut(0.0)) else scaleOut(NovaMotion.easeOut(0.14), 0.96f, androidx.compose.ui.graphics.TransformOrigin(0.85f, 0f))) {
            NovaPanelSurface(Modifier.statusBarsPadding().padding(top = 56.dp).padding(horizontal = 16.dp).widthIn(max = 440.dp),
                isPopover = true) {
                NovaNotificationsPanel(notices, canOpen, send, noticeNote, actions)
            }
        }
    }
}

/** One reusable popup surface: compact intrinsic height, scrolling at large text sizes. */
@Composable
fun NovaPanelSurface(modifier: Modifier = Modifier, isPopover: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    val radius = if (isPopover) 26.dp else 30.dp
    Column(modifier.fillMaxWidth().shadow(if (isPopover) 18.dp else 24.dp, RoundedCornerShape(radius),
            ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
        .clip(RoundedCornerShape(radius))
        .background(if (isPopover) NovaColorToken.canvasSheet.color() else NovaPopupStyle.background(), RoundedCornerShape(radius))
        .border(if (isPopover) 0.dp else 1.dp, NovaColorToken.glassBorder.color(), RoundedCornerShape(radius))
        .clickable(remember { MutableInteractionSource() }, null) {}
        .verticalScroll(rememberScrollState()).testTag("nova.panel.scroll")
        .padding(if (isPopover) 14.dp else 16.dp)) {
        CompositionLocalProvider(LocalNovaPopup provides !isPopover) { content() }
    }
}

@Composable
private fun NovaDrawer(selected: NovaDestination, canOpen: (NovaDestination) -> Boolean, userName: String,
                       avatar: ImageBitmap?, roleTitle: String, stats: List<NovaMenuStat>, nextAction: NovaMenuNextAction?,
                       send: (NovaNavigationEvent) -> Unit, isManager: Boolean, notebookAvailable: Boolean,
                       actions: NovaShellActions) {
    var expanded by remember { mutableStateOf<String?>(null) }
    val name = userName.ifBlank { "Kullanıcı" }
    val hairline = NovaColorToken.hairline.color()
    val go: (NovaDestination) -> Unit = { destination ->
        if (destination == NovaDestination.newCompany) actions.onCompanyCreate?.invoke()
        else { actions.onDestination?.invoke(destination); send(NovaNavigationEvent.Navigate(destination)) }
    }
    val openable: (NovaDestination) -> Boolean = { canOpen(it) && (it != NovaDestination.newCompany || actions.onCompanyCreate != null) }
    Column(Modifier.fillMaxHeight().safeDrawingPadding().padding(horizontal = 20.dp)) {
        Row(Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(46.dp).clip(CircleShape).background(Color(0xFF242424), CircleShape)
                .border(1.dp, hairline, CircleShape), contentAlignment = Alignment.Center) {
                if (avatar != null) Image(avatar, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                else NovaText(novaInitialsOf(name), style = NovaTypeToken.cardTitle, color = Color.White)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(name, style = NovaTypeToken.sectionTitle)
                NovaText(roleTitle, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color())
            }
            NovaPopupCloseButton(identifier = "nova.panel.close") { send(NovaNavigationEvent.Dismiss) }
        }
        if (stats.isNotEmpty()) Row(Modifier.padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            stats.take(3).forEach { stat ->
                val enabled = canOpen(stat.destination)
                Column(Modifier.weight(1f).heightIn(min = 54.dp).clip(RoundedCornerShape(14.dp))
                    .background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(14.dp))
                    .novaRowPress(enabled) {
                        actions.onDestination?.invoke(stat.destination)
                        send(NovaNavigationEvent.Navigate(stat.destination)); send(NovaNavigationEvent.Dismiss)
                    }.graphicsAlpha(if (enabled) 1f else 0.45f).testTag("nova.menu.stat.${stat.id}")
                    .padding(horizontal = 7.dp, vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(stat.symbol, 14.dp)
                        NovaText(stat.value, style = NovaTypeToken.metaQuiet, color = NovaColorToken.text.color())
                    }
                    NovaText(stat.title, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color(),
                        textAlign = TextAlign.Center, maxLines = 1)
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(hairline))
        Spacer(Modifier.height(7.dp))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).testTag("nova.panel.scroll")) {
            if (nextAction != null) {
                val enabled = nextAction.onSelect != null || openable(nextAction.destination)
                val accentInk = NovaColorToken.accentInk.color()
                val accent = NovaColorToken.accent.color()
                Column(Modifier.padding(bottom = 8.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp))
                    .background(accent.copy(alpha = 0.11f), RoundedCornerShape(16.dp))
                    .novaRowPress(enabled) { nextAction.onSelect?.invoke() ?: go(nextAction.destination); send(NovaNavigationEvent.Dismiss) }
                    .graphicsAlpha(if (enabled) 1f else 0.45f).testTag("nova.menu.next-action").padding(9.dp),
                    verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(26.dp).background(accent.copy(alpha = 0.16f), CircleShape), contentAlignment = Alignment.Center) {
                            NovaIcon(nextAction.symbol, 16.dp, tint = accentInk)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            NovaText("Sıradaki işin", style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color())
                            NovaText(nextAction.title, style = NovaTypeToken.body)
                        }
                        if (nextAction.total > 0) NovaText("${nextAction.completed}/${nextAction.total}", style = NovaTypeToken.metaQuiet, color = accentInk)
                        else NovaIcon("chevron.right", 12.dp, tint = accentInk)
                    }
                    if (nextAction.total > 0) {
                        val progress by animateFloatAsState(nextAction.progress, NovaMotion.easeOut(NovaMotion.Duration.progress), label = "nextAction")
                        LinearProgressIndicator({ progress }, Modifier.fillMaxWidth().height(5.dp), color = accentInk,
                            trackColor = accentInk.copy(alpha = 0.15f), strokeCap = StrokeCap.Round, gapSize = 0.dp, drawStopIndicator = {})
                    }
                }
            }
            if (isManager) {
                NovaDrawerSection("Genel")
                NovaDrawerRow(NovaDestination.home, selected, openable, go)
                NovaDrawerRow(NovaDestination.companies, selected, openable, go)
                NovaDrawerAction("Uzmanlar", "person.2", "nova.manager.experts", actions.onExpertCreate, send)
                NovaDrawerSection("İşlemler")
                NovaDrawerGroupView(NovaDrawerGroup("manager-analysis-audit", "Analiz & Denetim", "magnifyingglass",
                    listOf(NovaDestination.newAnalysis, NovaDestination.analyses, NovaDestination.newFinding, NovaDestination.findings)),
                    expanded, { expanded = it }, selected, openable, go)
                NovaDrawerGroupView(NovaDrawerGroup("manager-forms", "Formlar", "doc.text",
                    listOf(NovaDestination.ppeHandovers, NovaDestination.workPermits, NovaDestination.documentChecklist, NovaDestination.documents)),
                    expanded, { expanded = it }, selected, openable, go)
                NovaDrawerGroupView(NovaDrawerGroup("manager-safety", "İş Güvenliği", "shield.lefthalf.filled",
                    listOf(NovaDestination.riskAssessments, NovaDestination.emergencyPlans, NovaDestination.appointments,
                        NovaDestination.boardMeetings, NovaDestination.annualWorkPlans, NovaDestination.drills,
                        NovaDestination.periodicChecks, NovaDestination.katipContracts, NovaDestination.checklists)),
                    expanded, { expanded = it }, selected, openable, go)
                NovaDrawerSection("Takip")
                NovaDrawerRow(NovaDestination.training, selected, openable, go)
                NovaDrawerRow(NovaDestination.visits, selected, openable, go)
                NovaDrawerOperations(selected, openable, go, notebookAvailable)
                Box(Modifier.padding(horizontal = 8.dp, vertical = 8.dp).fillMaxWidth().height(1.dp).background(hairline))
                NovaText("Yönetim", Modifier.padding(horizontal = 8.dp).padding(bottom = 3.dp), NovaTypeToken.meta, NovaColorToken.textMuted.color())
                NovaDrawerAction("Firma ekle", "building.2.crop.circle", "nova.manager.add-company", actions.onCompanyCreate, send)
                NovaDrawerAction("Uzman ekle", "person.badge.plus", "nova.manager.add-expert", actions.onExpertCreate, send)
                NovaDrawerAction("Atama yap / değiştir", "person.2.badge.gearshape", "nova.manager.assign-expert", actions.onAssignmentOpen, send)
            } else {
                NovaDrawerSection("Genel")
                NovaDrawerRow(NovaDestination.home, selected, openable, go)
                NovaDrawerSection("İşlemler")
                NovaDrawerGroup.all.forEach { group -> NovaDrawerGroupView(group, expanded, { expanded = it }, selected, openable, go) }
                NovaDrawerSection("Takip")
                NovaDrawerRow(NovaDestination.training, selected, openable, go)
                NovaDrawerRow(NovaDestination.visits, selected, openable, go)
                NovaDrawerOperations(selected, openable, go, notebookAvailable)
            }
            actions.onInvite?.let { invite ->
                val accent = NovaColorToken.accent.color()
                Row(Modifier.padding(top = 6.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp))
                    .background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(16.dp))
                    .novaRowPress { invite(); send(NovaNavigationEvent.Dismiss) }.testTag("nova.menu.invite").padding(9.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.size(34.dp).background(accent.copy(alpha = 0.16f), CircleShape), contentAlignment = Alignment.Center) {
                        NovaIcon("gift", 20.dp, tint = NovaColorToken.accentInk.color())
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText("Arkadaşını Davet Et", style = NovaTypeToken.buttonSm)
                        NovaText("7 Günlük Plus kazan", style = NovaTypeToken.metaQuiet, color = NovaColorToken.textMuted.color())
                    }
                    NovaIcon("chevron.right", 15.dp)
                }
            }
        }
        Row(Modifier.padding(top = 6.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(42.dp, 40.dp).clip(RoundedCornerShape(13.dp))
                .background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(13.dp))
                .novaRowPress {
                    actions.onDestination?.invoke(NovaDestination.profile)
                    send(NovaNavigationEvent.Navigate(NovaDestination.profile)); send(NovaNavigationEvent.Dismiss)
                }.semantics { contentDescription = "Ayarlar" }.testTag("nova.settings"), contentAlignment = Alignment.Center) {
                NovaIcon("gearshape", 19.dp, tint = NovaColorToken.textSecondary.color())
            }
            Row(Modifier.weight(1f).heightIn(min = 40.dp).clip(CircleShape)
                .background(NovaColorToken.surfaceMuted.color(), CircleShape)
                .novaRowPress(actions.onLogout != null) { actions.onLogout?.invoke() }
                .graphicsAlpha(if (actions.onLogout == null) 0.4f else 1f).testTag("nova.logout"),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("rectangle.portrait.and.arrow.right", 18.dp, tint = NovaColorToken.statusDangerInk.color())
                NovaText("Çıkış yap", style = NovaTypeToken.body, color = NovaColorToken.statusDangerInk.color())
            }
        }
    }
}

@Composable
private fun NovaDrawerOperations(selected: NovaDestination, openable: (NovaDestination) -> Boolean,
                                 go: (NovaDestination) -> Unit, notebookAvailable: Boolean) {
    NovaDrawerSection("Operasyon")
    NovaDrawerRow(NovaDestination.statistics, selected, openable, go)
    NovaDrawerRow(NovaDestination.reports, selected, openable, go)
    NovaDrawerRow(NovaDestination.activity, selected, openable, go)
    if (notebookAvailable) NovaDrawerRow(NovaDestination.notebook, selected, openable, go)
}

@Composable
private fun NovaDrawerSection(title: String) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp).padding(top = 6.dp, bottom = 1.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(NovaColorToken.hairline.color()))
        NovaText(title, style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color())
    }
}

@Composable
private fun NovaDrawerRow(destination: NovaDestination, selected: NovaDestination, openable: (NovaDestination) -> Boolean,
                          go: (NovaDestination) -> Unit, nested: Boolean = false) {
    val enabled = openable(destination)
    Row(Modifier.fillMaxWidth().heightIn(min = 34.dp).novaRowPress(enabled) { go(destination) }
        .graphicsAlpha(if (enabled) 1f else 0.4f)
        .semantics { this.selected = selected == destination }.testTag("nova.destination.${destination.name}")
        .padding(start = if (nested) 24.dp else 8.dp, end = 8.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaIcon(destination.symbol, if (nested) 15.dp else 16.dp, Modifier.width(18.dp))
        NovaText(destination.title, Modifier.weight(1f), NovaTypeToken.metaQuiet, NovaColorToken.text.color())
        if (selected == destination) NovaIcon("checkmark", 13.dp)
    }
}

@Composable
private fun NovaDrawerAction(title: String, symbol: String, tag: String, action: (() -> Unit)?,
                             send: (NovaNavigationEvent) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 34.dp).novaRowPress(action != null) { action?.invoke(); send(NovaNavigationEvent.Dismiss) }
        .graphicsAlpha(if (action == null) 0.4f else 1f).testTag(tag).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaIcon(symbol, 16.dp, Modifier.width(18.dp))
        NovaText(title, Modifier.weight(1f), NovaTypeToken.body)
        NovaIcon("plus", 13.dp)
    }
}

@Composable
private fun NovaDrawerGroupView(group: NovaDrawerGroup, expanded: String?, onExpand: (String?) -> Unit,
                                selected: NovaDestination, openable: (NovaDestination) -> Boolean, go: (NovaDestination) -> Unit) {
    val open = expanded == group.id
    val reduceMotion = rememberNovaReduceMotion()
    val rotation by animateFloatAsState(if (open) 180f else 0f, NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion), label = "drawerGroup")
    Column {
        Row(Modifier.fillMaxWidth().heightIn(min = 36.dp).novaRowPress { onExpand(if (open) null else group.id) }
            .semantics { stateDescription = if (open) "Açık" else "Kapalı" }.testTag("nova.drawer.group.${group.id}")
            .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaIcon(group.symbol, 16.dp, Modifier.width(18.dp))
            NovaText(group.title, Modifier.weight(1f), NovaTypeToken.body)
            NovaIcon("chevron.down", 13.dp, Modifier.rotate(rotation))
        }
        AnimatedVisibility(open,
            enter = fadeIn(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion)) +
                expandVertically(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion), Alignment.Top),
            exit = fadeOut(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion)) +
                shrinkVertically(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion), Alignment.Top)) {
            Column(Modifier.padding(bottom = 2.dp)) {
                group.destinations.forEach { NovaDrawerRow(it, selected, openable, go, nested = true) }
            }
        }
    }
}

fun NovaDestination.quickHint(): String = when (this) {
    NovaDestination.newNote -> "Yalnız size ait not ve yapılacaklar"
    NovaDestination.newFinding -> "Bulgu, fotoğraf ve öncelik"
    NovaDestination.newDocument -> "Rapor, form veya belge yükle"
    NovaDestination.newVisit -> "Yeni saha ziyareti planla"
    NovaDestination.newTraining -> "Firma personeline eğitim kaydı oluştur"
    NovaDestination.newCompany -> "Yeni firma kaydı oluştur"
    NovaDestination.newAnalysis -> "Fotoğraflardan risk analizi oluştur"
    else -> ""
}
fun NovaDestination.quickSymbol(): String = when (this) {
    NovaDestination.newFinding -> "exclamationmark.triangle"
    NovaDestination.newDocument -> "doc.text"
    NovaDestination.newVisit -> "mappin"
    NovaDestination.newTraining -> "graduationcap"
    else -> symbol
}
fun NovaDestination.quickTone(): NovaColorToken = when (this) {
    NovaDestination.newDocument -> NovaColorToken.statusInfoDot
    NovaDestination.newVisit -> NovaColorToken.statusWarningDot
    else -> NovaColorToken.statusSuccessDot
}

@Composable
private fun NovaQuickAdd(canOpen: (NovaDestination) -> Boolean, send: (NovaNavigationEvent) -> Unit, isManager: Boolean,
                         notebookAvailable: Boolean, actions: NovaShellActions) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText("Ne eklemek istiyorsun?", Modifier.padding(horizontal = 4.dp).padding(bottom = 4.dp), NovaTypeToken.sectionTitle)
        if (isManager) {
            NovaQuickRow("Firma ekle", "Yeni firmayı ekleyin.", "building.2.crop.circle", NovaColorToken.accentInk,
                "nova.manager.quick.company", actions.onCompanyCreate != null) { actions.onCompanyCreate?.invoke(); send(NovaNavigationEvent.Dismiss) }
            NovaQuickRow("Uzman ekle", "Ekibinize yeni bir İSG uzmanı davet edin.", "person.badge.plus", NovaColorToken.accentInk,
                "nova.manager.quick.expert", actions.onExpertCreate != null) { actions.onExpertCreate?.invoke(); send(NovaNavigationEvent.Dismiss) }
            NovaQuickRow("Atama yap / değiştir", "Firma erişimi ve uzman rollerini yönetin.", "person.2.badge.gearshape", NovaColorToken.accentInk,
                "nova.manager.quick.assignment", actions.onAssignmentOpen != null) { actions.onAssignmentOpen?.invoke(); send(NovaNavigationEvent.Dismiss) }
        } else {
            NovaDestination.quickAdd.filter { it != NovaDestination.newNote || notebookAvailable }.forEach { destination ->
                val enabled = canOpen(destination) && (destination != NovaDestination.newCompany || actions.onCompanyCreate != null)
                NovaQuickRow(if (destination == NovaDestination.newFinding) "Uygunsuzluk Ekle" else destination.title,
                    destination.quickHint(), destination.quickSymbol(), destination.quickTone(),
                    "nova.destination.${destination.name}", enabled) {
                    if (destination == NovaDestination.newCompany) actions.onCompanyCreate?.invoke()
                    else { actions.onDestination?.invoke(destination); send(NovaNavigationEvent.Navigate(destination)) }
                }
            }
        }
        Row(Modifier.padding(top = 2.dp).fillMaxWidth().heightIn(min = 48.dp).clip(CircleShape)
            .background(NovaColorToken.surfaceMuted.color(), CircleShape)
            .novaRowPress { send(NovaNavigationEvent.Dismiss) }.testTag("nova.panel.close"),
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("chevron.left", 16.dp, tint = NovaColorToken.textSecondary.color())
            NovaText("Vazgeç", style = NovaTypeToken.button, color = NovaColorToken.textSecondary.color())
        }
    }
}

@Composable
private fun NovaQuickRow(title: String, detail: String, symbol: String, tone: NovaColorToken, tag: String,
                         enabled: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(RoundedCornerShape(20.dp)).novaControlBackground(20.dp)
        .novaRowPress(enabled, onClick = onClick).graphicsAlpha(if (enabled) 1f else 0.4f).testTag(tag)
        .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) { NovaIcon(symbol, 23.dp, tint = tone.color()) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            NovaSizedText(title, 15f, FontWeight.Medium)
            if (detail.isNotEmpty()) NovaText(detail, style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
        }
        NovaIcon("chevron.right", 14.dp, tint = NovaColorToken.borderStrong.color())
    }
}

@Composable
private fun NovaNotificationsPanel(notices: List<NovaNotice>, canOpen: (NovaDestination) -> Boolean,
                                   send: (NovaNavigationEvent) -> Unit, noticeNote: String, actions: NovaShellActions) {
    Column {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaText("Bildirimler", Modifier.weight(1f), NovaTypeToken.sectionTitle)
            NovaPopupCloseButton(identifier = "nova.panel.close") { send(NovaNavigationEvent.Dismiss) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End),
            verticalAlignment = Alignment.CenterVertically) {
            val canRead = actions.onReadAll != null && notices.isNotEmpty()
            val canClear = actions.onClearNotifications != null && notices.isNotEmpty()
            Box(Modifier.heightIn(min = 44.dp).novaRowPress(canRead) { actions.onReadAll?.invoke() }
                .graphicsAlpha(if (canRead) 1f else 0.4f).testTag("nova.notices.read"), contentAlignment = Alignment.Center) {
                NovaText("Tümünü oku", style = NovaTypeToken.meta, color = NovaColorToken.statusSuccessInk.color())
            }
            Box(Modifier.width(1.dp).height(14.dp).background(NovaColorToken.hairline.color()))
            Box(Modifier.heightIn(min = 44.dp).novaRowPress(canClear) { actions.onClearNotifications?.invoke() }
                .graphicsAlpha(if (canClear) 1f else 0.4f).testTag("nova.notices.clear"), contentAlignment = Alignment.Center) {
                NovaText("Bildirimleri sil", style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color())
            }
        }
        if (notices.isEmpty()) Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("bell", 17.dp, tint = NovaColorToken.textMuted.color())
            NovaText("Yeni bildirim yok", color = NovaColorToken.textMuted.color())
        }
        notices.forEach { notice -> NovaNoticeRow(notice, canOpen, send, actions) }
        if (noticeNote.isNotEmpty()) NovaSizedText(noticeNote, 10f, FontWeight.Normal, NovaColorToken.textMuted.color(),
            Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp))
        val center = canOpen(NovaDestination.notifications)
        Row(Modifier.heightIn(min = 44.dp).novaRowPress(center) { send(NovaNavigationEvent.Navigate(NovaDestination.notifications)) }
            .graphicsAlpha(if (center) 1f else 0.4f).testTag("nova.notices.center"),
            horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaText("Bildirim merkezine git", style = NovaTypeToken.meta, color = NovaColorToken.statusSuccessInk.color())
            NovaIcon("arrow.right", 13.dp, tint = NovaColorToken.statusSuccessInk.color())
        }
    }
}

@Composable
private fun NovaNoticeRow(notice: NovaNotice, canOpen: (NovaDestination) -> Boolean, send: (NovaNavigationEvent) -> Unit,
                          actions: NovaShellActions) {
    Row(Modifier.padding(bottom = 7.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).novaControlBackground(20.dp)
        .graphicsAlpha(if (notice.dismissed) 0.55f else 1f).padding(horizontal = 12.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        val enabled = canOpen(notice.destination)
        Row(Modifier.weight(1f).novaRowPress(enabled) {
            // Opening a notice is reading it.
            actions.onReadNotice?.invoke(notice.id)
            send(NovaNavigationEvent.Navigate(notice.destination)); send(NovaNavigationEvent.Dismiss)
            actions.onOpenNotice?.invoke(notice.id)
        }.testTag("nova.notice.${notice.id}"), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
                NovaIcon(notice.symbol, 20.dp, tint = notice.tone.color())
                if (notice.unread) Box(Modifier.align(Alignment.TopEnd).size(5.dp).background(NovaColorToken.statusDangerDot.color(), CircleShape))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    NovaSizedText(notice.title, 13f, if (notice.unread) FontWeight.Bold else FontWeight.Medium, modifier = Modifier.weight(1f))
                    NovaSizedText(notice.badge, 10f, FontWeight.Bold, notice.tone.color())
                }
                NovaSizedText(notice.detail, 11f, FontWeight.Normal, NovaColorToken.textMuted.color())
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (notice.dismissed) {
                NovaNoticeAction("arrow.uturn.backward", "Geri al", "nova.notice.restore.${notice.id}", actions.onRestoreNotice == null) {
                    actions.onRestoreNotice?.invoke(notice.id)
                }
            } else {
                NovaNoticeAction(if (notice.unread) "envelope.open" else "envelope", "Okundu işaretle", "nova.notice.read.${notice.id}",
                    actions.onReadNotice == null || !notice.unread) { actions.onReadNotice?.invoke(notice.id) }
                NovaNoticeAction("trash", "Bildirimi sil", "nova.notice.dismiss.${notice.id}", actions.onDismissNotice == null) {
                    actions.onDismissNotice?.invoke(notice.id)
                }
            }
        }
    }
}

@Composable
private fun NovaNoticeAction(symbol: String, label: String, tag: String, disabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(30.dp).novaRowPress(!disabled, onClick = onClick).graphicsAlpha(if (disabled) 0.4f else 1f)
        .semantics { contentDescription = label }.testTag(tag), contentAlignment = Alignment.Center) {
        NovaIcon(symbol, 14.dp, tint = NovaColorToken.textMuted.color())
    }
}

internal fun novaInitials(name: String) = novaInitialsOf(name)

/** Page title reuses the destination glyph; never an icon background tile. */
@Composable
fun NovaPageTitle(destination: NovaDestination, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaIcon(destination.symbol, 22.dp, tint = NovaColorToken.accent.color())
        NovaText(destination.title, style = NovaTypeToken.screenTitle)
    }
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

/** Exact OSGB source vectors for the legacy destination screens that still use Material names. */
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
