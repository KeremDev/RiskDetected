package com.riskdetectedan.core.designsystem.isg

// Expert shell presentation state. Availability is NOT server authorization.
enum class NovaTab(val title: String) {
    home("Ana Sayfa"),
    findings("Denetim"),
    companies("Firmalar"),
    profile("Profil");
    val root: NovaDestination get() = NovaDestination.valueOf(name)
}

/** Generated from iOS `NovaNavigation.swift` — order, titles, tabs and symbols match. */
enum class NovaDestination(val title: String, val tab: NovaTab, val symbol: String) {
    activity("Aktivitem", NovaTab.profile, "clock.arrow.circlepath"),
    notebook("Kişisel Not Defteri", NovaTab.profile, "note.text"),
    newNote("Not ekle", NovaTab.profile, "note.text"),
    home("Ana Sayfa", NovaTab.home, "house"),
    newFinding("Uygunsuzluk Ekle", NovaTab.findings, "exclamationmark.triangle"),
    findings("Uygunsuzluklar", NovaTab.findings, "list.bullet"),
    companies("Firmalar", NovaTab.companies, "building.2"),
    memory("İşletme Hafızası", NovaTab.home, "clock.arrow.circlepath"),
    documentChecklist("Evrak Takibi", NovaTab.home, "doc.text"),
    documents("Dosyalarım", NovaTab.home, "folder"),
    visits("Ziyaretler", NovaTab.home, "mappin.and.ellipse"),
    statistics("İstatistikler", NovaTab.home, "chart.bar"),
    training("Eğitim ve Takip", NovaTab.home, "graduationcap"),
    reports("Rapor Merkezi", NovaTab.home, "chart.bar"),
    reportArchive("Rapor Arşivi", NovaTab.home, "archivebox"),
    notifications("Bildirim Merkezi", NovaTab.home, "bell"),
    profile("Profil", NovaTab.profile, "person"),
    newDocument("Dosya Ekle", NovaTab.home, "doc.badge.plus"),
    newVisit("Ziyaret Ekle", NovaTab.home, "calendar.badge.plus"),
    newTraining("Eğitim Ekle", NovaTab.home, "graduationcap"),
    periodicChecks("Periyodik Kontroller", NovaTab.home, "checkmark.shield"),
    newCompany("Firma Ekle", NovaTab.companies, "building.2"),
    riskAssessments("Risk Değerlendirmesi", NovaTab.home, "shield.lefthalf.filled"),
    checklists("Kontrol Listeleri", NovaTab.home, "checklist"),
    emergencyPlans("Acil Durum Planları", NovaTab.home, "light.beacon.max"),
    drills("Tatbikatlar", NovaTab.home, "figure.run"),
    ppeHandovers("KKD Zimmet Formları", NovaTab.home, "shield.checkered"),
    appointments("Atama ve Temsilciler", NovaTab.home, "person.badge.shield.checkmark"),
    katipContracts("İSG-KATİP Sözleşmeleri", NovaTab.home, "doc.text.magnifyingglass"),
    annualWorkPlans("Yıllık Çalışma Planı", NovaTab.home, "calendar"),
    boardMeetings("Kurul ve Toplantılar", NovaTab.home, "person.3"),
    workPermits("Çalışma İzni Formları", NovaTab.home, "doc.text"),
    contractors("Taşeron ve Dış Firmalar", NovaTab.home, "building.2"),
    analyses("Analizlerim", NovaTab.findings, "photo.on.rectangle.angled"),
    newAnalysis("Analiz Yap", NovaTab.findings, "camera");
    companion object {
        // Historical route values remain decodable; removed product features are not offered.
        val drawer = listOf(home, findings, analyses, newAnalysis, newFinding, companies, newCompany, riskAssessments,
            checklists, emergencyPlans, drills, ppeHandovers, appointments, katipContracts, annualWorkPlans, boardMeetings,
            visits, workPermits, contractors, periodicChecks, documentChecklist, documents, statistics, training, reports,
            reportArchive, notifications)
        val quickAdd = listOf(newCompany, newAnalysis, newFinding, newDocument, newNote)
    }
}

/**
 * The panel is one product surface; roles only change which capabilities are
 * exposed, so a new module cannot silently exist in one panel only.
 */
enum class NovaWorkspaceRole {
    personnel, osgbExpert, osgbManager;

    val destinations: Set<NovaDestination> get() = when (this) {
        personnel, osgbManager -> sharedDestinations
        // An OSGB expert operates the same modules but cannot create an OSGB company.
        osgbExpert -> sharedDestinations - NovaDestination.newCompany
    }

    companion object {
        val sharedDestinations: Set<NovaDestination> = setOf(
            NovaDestination.activity, NovaDestination.notebook, NovaDestination.newNote, NovaDestination.riskAssessments, NovaDestination.statistics, NovaDestination.companies, NovaDestination.newCompany, NovaDestination.findings, NovaDestination.newFinding,
            NovaDestination.analyses, NovaDestination.newAnalysis, NovaDestination.training, NovaDestination.newTraining, NovaDestination.documentChecklist, NovaDestination.documents, NovaDestination.newDocument, NovaDestination.periodicChecks,
            NovaDestination.emergencyPlans, NovaDestination.drills, NovaDestination.ppeHandovers, NovaDestination.appointments, NovaDestination.katipContracts, NovaDestination.annualWorkPlans, NovaDestination.boardMeetings, NovaDestination.visits,
            NovaDestination.workPermits, NovaDestination.contractors, NovaDestination.reports, NovaDestination.reportArchive, NovaDestination.checklists, NovaDestination.notifications, NovaDestination.newVisit)
    }
}

/** Each drawer destination appears once; grouping does not alter route identities. */
data class NovaDrawerGroup(val id: String, val title: String, val symbol: String, val destinations: List<NovaDestination>) {
    companion object {
        val all: List<NovaDrawerGroup> = listOf(
            NovaDrawerGroup("analysis-audit", "Analiz & Denetim", "magnifyingglass", listOf(NovaDestination.newAnalysis, NovaDestination.analyses, NovaDestination.newFinding, NovaDestination.findings)),
            NovaDrawerGroup("company", "Firma", "building.2", listOf(NovaDestination.newCompany, NovaDestination.companies, NovaDestination.contractors)),
            NovaDrawerGroup("forms", "Formlar", "doc.text", listOf(NovaDestination.ppeHandovers, NovaDestination.workPermits, NovaDestination.documentChecklist, NovaDestination.documents)),
            NovaDrawerGroup("safety", "İş Güvenliği", "shield.lefthalf.filled", listOf(NovaDestination.riskAssessments, NovaDestination.emergencyPlans,
                NovaDestination.appointments, NovaDestination.boardMeetings, NovaDestination.annualWorkPlans, NovaDestination.drills, NovaDestination.periodicChecks, NovaDestination.katipContracts, NovaDestination.checklists)),
        )
        /** Destinations rendered by the shell's named sections; Bildirim Merkezi is owned by Profil. */
        val direct: List<NovaDestination> = listOf(NovaDestination.home, NovaDestination.training, NovaDestination.visits, NovaDestination.statistics, NovaDestination.reports, NovaDestination.activity, NovaDestination.notebook)
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
