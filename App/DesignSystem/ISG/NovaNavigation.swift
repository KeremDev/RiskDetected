// Expert shell presentation state. Availability is NOT server authorization.
import Foundation

enum NovaTab: String, CaseIterable, Hashable {
    case home, findings, companies, profile
    var root: NovaDestination { NovaDestination(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .home: return RDLocalization.string("localizable.nova.navigation.ana.sayfa.32b7f210", table: .localizable, fallback: "Ana Sayfa")
        case .findings: return "Denetim"
        case .companies: return "Firmalar"
        case .profile: return "Profil"
        }
    }
}

enum NovaDestination: String, CaseIterable, Hashable {
    case activity, notebook, newNote
    case home, newFinding, findings, companies, memory, documentChecklist, documents, visits, statistics, training, reports, reportArchive, notifications, profile, newDocument, newVisit, newTraining
    case periodicChecks, newCompany
    /// P08: the workplace risk assessment record and its versions.
    case riskAssessments
    /// P09: the expert's own question lists and the runs filled against them.
    case checklists
    /// P10: the versioned emergency plan and the team frozen into it.
    case emergencyPlans
    /// P10: drills rehearsing a pinned version of an emergency plan.
    case drills
    /// P10: protective equipment handed to a person and what came back.
    case ppeHandovers
    /// P10: who holds a safety role, in which scope and on what basis.
    case appointments
    /// P10: the expert's own record of the İSG hizmet sözleşmesi.
    case katipContracts
    case annualWorkPlans, boardMeetings, workPermits, contractors
    /// The analysis surfaces are their own menu entries: one lists what was
    /// analysed, the other starts a new one.
    case analyses, newAnalysis
    var title: String {
        switch self {
        case .activity: return "Aktivitem"
        case .notebook: return RDLocalization.string("localizable.nova.navigation.notebook", table: .localizable, fallback: "Kişisel Not Defteri")
        case .newNote: return RDLocalization.string("localizable.nova.navigation.not.ekle.404f9b06", table: .localizable, fallback: "Not ekle")
        case .newCompany: return RDLocalization.string("localizable.nova.navigation.firma.ekle.b4073323", table: .localizable, fallback: "Firma Ekle")
        case .periodicChecks: return RDLocalization.string("localizable.nova.navigation.periodic.checks", table: .localizable, fallback: "Periyodik Kontroller")
        case .riskAssessments: return RDLocalization.string("localizable.nova.navigation.risk.assessments", table: .localizable, fallback: "Risk Değerlendirmesi")
        case .checklists: return RDLocalization.string("localizable.nova.navigation.checklists", table: .localizable, fallback: "Kontrol Listeleri")
        case .emergencyPlans: return RDLocalization.string("localizable.nova.navigation.emergency.plans", table: .localizable, fallback: "Acil Durum Planları")
        case .drills: return RDLocalization.string("localizable.nova.navigation.drills", table: .localizable, fallback: "Tatbikatlar")
        case .ppeHandovers: return RDLocalization.string("localizable.nova.navigation.kkd.zimmet.formu.ornegi.58655993", table: .localizable, fallback: "KKD Zimmet Formu Örneği")
        case .appointments: return RDLocalization.string("localizable.nova.navigation.appointments", table: .localizable, fallback: "Atama ve Temsilciler")
        case .annualWorkPlans: return RDLocalization.string("localizable.nova.navigation.annual.work.plans", table: .localizable, fallback: "Yıllık Çalışma Planı")
        case .boardMeetings: return RDLocalization.string("localizable.nova.navigation.board.meetings", table: .localizable, fallback: "Kurul ve Toplantılar")
        case .workPermits: return RDLocalization.string("localizable.nova.navigation.calisma.izni.ornekleri.ac7d5ad4", table: .localizable, fallback: "Çalışma İzni Örnekleri")
        case .contractors: return RDLocalization.string("localizable.nova.navigation.contractors", table: .localizable, fallback: "Taşeron ve Dış Firmalar")
        case .katipContracts: return RDLocalization.string("localizable.nova.navigation.katip", table: .localizable, fallback: "İSG-KATİP Sözleşmeleri")
        case .home: return RDLocalization.string("localizable.nova.navigation.ana.sayfa.1fc29356", table: .localizable, fallback: "Ana Sayfa")
        case .newFinding: return RDLocalization.string("localizable.nova.navigation.uygunsuzluk.ekle", table: .localizable, fallback: "Uygunsuzluk Ekle")
        case .analyses: return RDLocalization.string("localizable.nova.navigation.analizlerim", table: .localizable, fallback: "Analizlerim")
        case .newAnalysis: return RDLocalization.string("localizable.nova.navigation.analiz.yap", table: .localizable, fallback: "Analiz Yap")
        case .findings: return "Uygunsuzluklar"
        case .companies: return "Firmalar"
        case .memory: return RDLocalization.string("localizable.nova.navigation.isletme.hafizasi.c231f5c8", table: .localizable, fallback: "İşletme Hafızası")
        case .documentChecklist: return RDLocalization.string("localizable.nova.navigation.evrak.takibi.1d59a02d", table: .localizable, fallback: "Evrak Takibi")
        case .documents: return RDLocalization.string("localizable.nova.navigation.diger.dosyalar.f5089207", table: .localizable, fallback: "Dosyalarım")
        case .visits: return "Ziyaretler"
        case .statistics: return RDLocalization.string("localizable.nova.navigation.istatistikler.da698529", table: .localizable, fallback: "İstatistikler")
        case .training: return RDLocalization.string("localizable.nova.navigation.egitim.ve.takip.59c46410", table: .localizable, fallback: "Eğitim ve Takip")
        case .reports: return RDLocalization.string("localizable.nova.navigation.rapor.merkezi.883944ff", table: .localizable, fallback: "Rapor Merkezi")
        case .reportArchive: return RDLocalization.string("localizable.nova.navigation.rapor.arsivi.67865663", table: .localizable, fallback: "Rapor Arşivi")
        case .notifications: return RDLocalization.string("localizable.nova.navigation.bildirim.merkezi.e5d0ac4c", table: .localizable, fallback: "Bildirim Merkezi")
        case .profile: return "Profil"
        case .newDocument: return RDLocalization.string("localizable.nova.navigation.dosya.ekle.1d00b6f7", table: .localizable, fallback: "Dosya Ekle")
        case .newVisit: return RDLocalization.string("localizable.nova.navigation.ziyaret.ekle.061f46a5", table: .localizable, fallback: "Ziyaret Ekle")
        case .newTraining: return RDLocalization.string("localizable.nova.navigation.egitim.ekle.5662b38f", table: .localizable, fallback: "Eğitim Ekle")
        }
    }
    var tab: NovaTab {
        switch self {
        case .activity, .notebook, .newNote: return .profile
        case .newCompany: return .companies
        case .periodicChecks: return .home
        case .riskAssessments: return .home
        case .checklists: return .home
        case .emergencyPlans: return .home
        case .drills: return .home
        case .ppeHandovers: return .home
        case .appointments, .katipContracts, .annualWorkPlans, .boardMeetings, .workPermits, .contractors: return .home
        case .home: return .home
        case .newFinding: return .findings
        case .analyses: return .findings
        case .newAnalysis: return .findings
        case .findings: return .findings
        case .companies: return .companies
        case .memory: return .home
        case .documentChecklist: return .home
        case .documents: return .home
        case .visits: return .home
        case .statistics: return .home
        case .training: return .home
        case .reports: return .home
        case .reportArchive: return .home
        case .notifications: return .home
        case .profile: return .profile
        case .newDocument: return .home
        case .newVisit: return .home
        case .newTraining: return .home
        }
    }
    var symbol: String {
        switch self {
        case .activity: return "clock.arrow.circlepath"
        case .notebook, .newNote: return "note.text"
        case .newCompany: return "building.2"
        case .periodicChecks: return "checkmark.shield"
        case .riskAssessments: return "shield.lefthalf.filled"
        case .checklists: return "checklist"
        case .emergencyPlans: return "light.beacon.max"
        case .drills: return "figure.run"
        case .ppeHandovers: return "shield.checkered"
        case .appointments: return "person.badge.shield.checkmark"
        case .katipContracts: return "doc.text.magnifyingglass"
        case .annualWorkPlans: return "calendar"
        case .boardMeetings: return "person.3"
        case .workPermits: return "doc.text"
        case .contractors: return "building.2"
        case .home: return "house"
        case .newFinding: return "exclamationmark.triangle"
        case .analyses: return "photo.on.rectangle.angled"
        case .newAnalysis: return "camera"
        case .findings: return "list.bullet"
        case .companies: return "building.2"
        case .memory: return "clock.arrow.circlepath"
        case .documentChecklist: return "doc.text"
        case .documents: return "folder"
        case .visits: return "mappin.and.ellipse"
        case .statistics: return "chart.bar"
        case .training: return "graduationcap"
        case .reports: return "chart.bar"
        case .reportArchive: return "archivebox"
        case .notifications: return "bell"
        case .profile: return "person"
        case .newDocument: return "doc.badge.plus"
        case .newVisit: return "calendar.badge.plus"
        case .newTraining: return "graduationcap"
        }
    }
    // Historical route values remain decodable; removed product features are not offered.
    static let drawer: [Self] = [.home, .findings, .analyses, .newAnalysis, .newFinding, .companies, .newCompany, .riskAssessments, .checklists, .emergencyPlans, .drills, .ppeHandovers, .appointments, .katipContracts, .annualWorkPlans, .boardMeetings, .visits, .workPermits, .contractors, .periodicChecks, .documentChecklist, .documents, .statistics, .training, .reports, .reportArchive, .notifications]
    static let quickAdd: [Self] = [.newCompany, .newAnalysis, .newFinding, .newDocument, .newNote]
}

/// The panel is a product surface, not a role-specific screen.  Roles only
/// change which capabilities are exposed; every workspace starts from this
/// same route catalog so a new module cannot silently exist in one panel only.
enum NovaWorkspaceRole: String, CaseIterable {
    case personnel
    case osgbExpert
    case osgbManager

    /// Routes shared by both the personal/personnel and OSGB workspaces.
    /// Management actions are capability-gated at the shell, while the
    /// operational pages remain available to every authorized expert.
    static let sharedDestinations: Set<NovaDestination> = [
        .activity, .notebook, .newNote,
        .riskAssessments, .statistics, .companies, .newCompany,
        .findings, .newFinding, .analyses, .newAnalysis,
        .training, .newTraining, .documentChecklist, .documents, .newDocument,
        .periodicChecks, .emergencyPlans, .drills, .ppeHandovers, .appointments,
        .katipContracts, .annualWorkPlans, .boardMeetings, .visits, .workPermits,
        .contractors, .reports, .reportArchive, .checklists, .notifications,
        .newVisit
    ]

    var destinations: Set<NovaDestination> {
        switch self {
        case .personnel, .osgbManager:
            return Self.sharedDestinations
        case .osgbExpert:
            // An OSGB expert can operate the same modules but cannot create
            // an OSGB company or manage the tenant directory. Operational AI
            // analysis remains available through the tenant-scoped product
            // endpoint and the expert's active company assignment.
            return Self.sharedDestinations.subtracting([.newCompany])
        }
    }
}

/// Each drawer destination appears once; grouping does not alter route identities.
struct NovaDrawerGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let destinations: [NovaDestination]

    static var all: [Self] {
        // Written as literal keys, not a prefix + id concatenation: the
        // catalog scanner can only verify a key it can read whole.
        [
            .init(id: "analysis-audit",
                  title: RDLocalization.string("localizable.nova.drawer.group.analysis.audit", table: .localizable, fallback: "Analiz & Denetim"),
                  symbol: "magnifyingglass",
                  destinations: [.newAnalysis, .analyses, .newFinding, .findings]),
            .init(id: "company",
                  title: RDLocalization.string("localizable.nova.drawer.group.company", table: .localizable, fallback: "Firma"),
                  symbol: "building.2",
                  destinations: [.newCompany, .companies, .contractors]),
            .init(id: "forms",
                  title: RDLocalization.string("localizable.nova.drawer.group.forms", table: .localizable, fallback: "Formlar"),
                  symbol: "doc.text",
                  destinations: [.ppeHandovers, .workPermits, .documentChecklist, .documents]),
            .init(id: "safety",
                  title: RDLocalization.string("localizable.nova.drawer.group.safety", table: .localizable, fallback: "İş Güvenliği"),
                  symbol: "shield.lefthalf.filled",
                  destinations: [.riskAssessments, .emergencyPlans, .appointments, .boardMeetings, .annualWorkPlans, .drills,
                                 .periodicChecks, .katipContracts, .checklists])
        ]
    }
    /// Destinations rendered by the shell's named sections. Bildirim Merkezi
    /// intentionally stays out of the drawer and is owned by Profil.
    static let direct: [NovaDestination] = [.home, .training, .visits, .statistics, .reports, .activity, .notebook]
}

enum NovaOverlay: String, CaseIterable { case drawer, quickAdd, notifications }

enum NovaNavigationEvent {
    case select(NovaTab), open(NovaOverlay), navigate(NovaDestination), back, dismiss
}

struct NovaNavigationState: Equatable {
    private(set) var epoch: String
    private(set) var selected: NovaTab = .home
    private(set) var overlay: NovaOverlay?
    private(set) var available: Set<NovaDestination>
    private(set) var paths: [NovaTab: [NovaDestination]] = Dictionary(uniqueKeysWithValues: NovaTab.allCases.map { ($0, []) })

    init(epoch: String, available: Set<NovaDestination>) {
        self.epoch = epoch
        self.available = available.union([.home, .profile])
    }
    var current: NovaDestination { paths[selected]?.last ?? selected.root }
    mutating func apply(_ event: NovaNavigationEvent, from expectedEpoch: String) {
        switch event {
        case .select(let tab): select(tab, from: expectedEpoch)
        case .open(let panel): open(panel, from: expectedEpoch)
        case .navigate(let destination): navigate(destination, from: expectedEpoch)
        case .back: back(from: expectedEpoch)
        case .dismiss: dismiss(from: expectedEpoch)
        }
    }
    var canGoBack: Bool { overlay != nil || !(paths[selected] ?? []).isEmpty || selected != .home }
    func canOpen(_ destination: NovaDestination) -> Bool {
        return available.contains(destination) && available.contains(destination.tab.root)
    }
    mutating func select(_ tab: NovaTab, from expectedEpoch: String) {
        guard expectedEpoch == epoch, canOpen(tab.root) else { return }
        overlay = nil
        // Reselect is an explicit return to this tab's root; other paths survive.
        if selected == tab { paths[tab] = [] }
        selected = tab
    }
    mutating func open(_ panel: NovaOverlay, from expectedEpoch: String) {
        guard expectedEpoch == epoch else { return }
        overlay = panel
    }
    mutating func dismiss(from expectedEpoch: String) {
        guard expectedEpoch == epoch else { return }
        overlay = nil
    }
    mutating func navigate(_ destination: NovaDestination, from expectedEpoch: String) {
        guard expectedEpoch == epoch, canOpen(destination) else { return }
        overlay = nil
        selected = destination.tab
        if destination == selected.root { paths[selected] = [] }
        else if current != destination { paths[selected, default: []].append(destination) }
    }
    mutating func back(from expectedEpoch: String) {
        guard expectedEpoch == epoch else { return }
        if overlay != nil { overlay = nil }
        else if !(paths[selected] ?? []).isEmpty { paths[selected]?.removeLast() }
        else { selected = .home }
    }
    // NavigationStack may only shorten its existing path, never inject a destination.
    mutating func acceptBackPath(_ path: [NovaDestination], tab: NovaTab, from expectedEpoch: String) {
        let old = paths[tab] ?? []
        guard expectedEpoch == epoch, tab == selected, path.count <= old.count,
              Array(old.prefix(path.count)) == path else { return }
        paths[tab] = path
    }
    mutating func updateAvailability(_ values: Set<NovaDestination>, from expectedEpoch: String) {
        guard expectedEpoch == epoch else { return }
        available = values.union([.home, .profile])
        overlay = nil
        for tab in NovaTab.allCases {
            // Removing an ancestor also removes every child, not just that one element.
            paths[tab] = Array((paths[tab] ?? []).prefix { canOpen($0) })
        }
        if !canOpen(selected.root) { selected = .home }
    }
    mutating func resetAccount(to newEpoch: String, available values: Set<NovaDestination>) {
        guard newEpoch != epoch else { return }
        self = Self(epoch: newEpoch, available: values)
    }
}
