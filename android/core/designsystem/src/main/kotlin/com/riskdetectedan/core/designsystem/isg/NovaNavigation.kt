package com.riskdetectedan.core.designsystem.isg

// Expert shell presentation state. Availability is NOT server authorization.
enum class NovaTab(val title: String) {
    home("Ana Sayfa"),
    findings("Uygunsuzluk"),
    companies("Firmalar"),
    profile("Profil");
    val root: NovaDestination get() = NovaDestination.valueOf(name)
}
enum class NovaDestination(val title: String, val tab: NovaTab) {
    home("Ana Sayfa", NovaTab.home),
    newFinding("Yeni Uygunsuzluk", NovaTab.findings),
    findings("Uygunsuzluklar", NovaTab.findings),
    companies("Firmalar", NovaTab.companies),
    memory("İşletme Hafızası", NovaTab.home),
    documentChecklist("Evrak Takibi", NovaTab.home),
    documents("Diğer Dosyalar", NovaTab.home),
    visits("Ziyaretler", NovaTab.home),
    statistics("İstatistikler", NovaTab.home),
    training("Eğitim ve Takip", NovaTab.home),
    reports("Rapor Oluştur", NovaTab.home),
    reportArchive("Rapor Arşivi", NovaTab.home),
    notifications("Bildirim Merkezi", NovaTab.home),
    profile("Profil", NovaTab.profile),
    newDocument("Dosya Ekle", NovaTab.home),
    newVisit("Ziyaret Ekle", NovaTab.home),
    newTraining("Eğitim Ekle", NovaTab.home),
    periodicChecks("Periyodik Kontroller", NovaTab.home);
    companion object {
        val drawer = listOf(home, newFinding, findings, companies, periodicChecks, documentChecklist, documents, statistics, training, reports, reportArchive, notifications)
        val quickAdd = listOf(newFinding, newDocument, newTraining)
    }
}
enum class NovaOverlay { drawer, quickAdd, notifications }

sealed interface NovaNavigationEvent {
    data class Select(val tab: NovaTab) : NovaNavigationEvent
    data class Open(val panel: NovaOverlay) : NovaNavigationEvent
    data class Navigate(val destination: NovaDestination) : NovaNavigationEvent
    data object Back : NovaNavigationEvent
    data object Dismiss : NovaNavigationEvent
}

// Immutable snapshots are assigned back into Compose state; no global router/singleton.
@ConsistentCopyVisibility
data class NovaNavigationState private constructor(
    val epoch: String,
    val selected: NovaTab,
    val overlay: NovaOverlay?,
    val available: Set<NovaDestination>,
    val paths: Map<NovaTab, List<NovaDestination>>,
) {
    constructor(epoch: String, available: Set<NovaDestination>) : this(epoch, NovaTab.home, null,
        available.toSet() + setOf(NovaDestination.home, NovaDestination.profile), NovaTab.entries.associateWith { emptyList() })
    val current: NovaDestination get() = paths[selected]?.lastOrNull() ?: selected.root
    fun apply(event: NovaNavigationEvent, from: String): NovaNavigationState = when (event) {
        is NovaNavigationEvent.Select -> select(event.tab, from)
        is NovaNavigationEvent.Open -> open(event.panel, from)
        is NovaNavigationEvent.Navigate -> navigate(event.destination, from)
        NovaNavigationEvent.Back -> back(from)
        NovaNavigationEvent.Dismiss -> dismiss(from)
    }
    val canGoBack: Boolean get() = overlay != null || !paths[selected].isNullOrEmpty() || selected != NovaTab.home
    fun canOpen(destination: NovaDestination) = destination in available && destination.tab.root in available
    fun select(tab: NovaTab, from: String): NovaNavigationState {
        if (from != epoch || !canOpen(tab.root)) return this
        return copy(selected = tab, overlay = null, paths = if (selected == tab) paths + (tab to emptyList()) else paths)
    }
    fun open(panel: NovaOverlay, from: String) = if (from == epoch) copy(overlay = panel) else this
    fun dismiss(from: String) = if (from == epoch) copy(overlay = null) else this
    fun navigate(destination: NovaDestination, from: String): NovaNavigationState {
        if (from != epoch || !canOpen(destination)) return this
        val tab = destination.tab
        val old = paths.getValue(tab)
        val next = if (destination == tab.root) emptyList() else if ((old.lastOrNull() ?: tab.root) == destination) old else old + destination
        return copy(selected = tab, overlay = null, paths = paths + (tab to next))
    }
    fun back(from: String): NovaNavigationState {
        if (from != epoch) return this
        if (overlay != null) return copy(overlay = null)
        val old = paths.getValue(selected)
        return if (old.isNotEmpty()) copy(paths = paths + (selected to old.dropLast(1))) else copy(selected = NovaTab.home)
    }
    fun acceptBackPath(path: List<NovaDestination>, tab: NovaTab, from: String): NovaNavigationState {
        val old = paths.getValue(tab)
        if (from != epoch || tab != selected || path.size > old.size || old.take(path.size) != path) return this
        return copy(paths = paths + (tab to path.toList()))
    }
    fun updateAvailability(values: Set<NovaDestination>, from: String): NovaNavigationState {
        if (from != epoch) return this
        val next = copy(available = values.toSet() + setOf(NovaDestination.home, NovaDestination.profile), overlay = null)
        return next.copy(selected = if (next.canOpen(selected.root)) selected else NovaTab.home,
            paths = paths.mapValues { (_, path) -> path.takeWhile { next.canOpen(it) } })
    }
    fun resetAccount(newEpoch: String, values: Set<NovaDestination>) =
        if (newEpoch == epoch) this else NovaNavigationState(newEpoch, values)
}
