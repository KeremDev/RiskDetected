// Expert shell presentation state. Availability is NOT server authorization.
import Foundation

enum NovaTab: String, CaseIterable, Hashable {
    case home, findings, companies, profile
    var root: NovaDestination { NovaDestination(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .findings: return "Uygunsuzluk"
        case .companies: return "Firmalar"
        case .profile: return "Profil"
        }
    }
}

enum NovaDestination: String, CaseIterable, Hashable {
    case home, newFinding, findings, companies, memory, documentChecklist, documents, visits, statistics, training, reports, reportArchive, notifications, profile, newDocument, newVisit, newTraining
    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .newFinding: return "Yeni Uygunsuzluk"
        case .findings: return "Uygunsuzluklar"
        case .companies: return "Firmalar"
        case .memory: return "İşletme Hafızası"
        case .documentChecklist: return "Evrak Takibi"
        case .documents: return "Diğer Dosyalar"
        case .visits: return "Ziyaretler"
        case .statistics: return "İstatistikler"
        case .training: return "Eğitim ve Takip"
        case .reports: return "Rapor Oluştur"
        case .reportArchive: return "Rapor Arşivi"
        case .notifications: return "Bildirim Merkezi"
        case .profile: return "Profil"
        case .newDocument: return "Dosya Ekle"
        case .newVisit: return "Ziyaret Ekle"
        case .newTraining: return "Eğitim Ekle"
        }
    }
    var tab: NovaTab {
        switch self {
        case .home: return .home
        case .newFinding: return .findings
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
        case .home: return "house"
        case .newFinding: return "camera"
        case .findings: return "list.bullet"
        case .companies: return "building.2"
        case .memory: return "clock.arrow.circlepath"
        case .documentChecklist: return "doc.text"
        case .documents: return "folder"
        case .visits: return "mappin.and.ellipse"
        case .statistics: return "chart.bar"
        case .training: return "graduationcap"
        case .reports: return "chart.doc"
        case .reportArchive: return "archivebox"
        case .notifications: return "bell"
        case .profile: return "person"
        case .newDocument: return "doc.badge.plus"
        case .newVisit: return "calendar.badge.plus"
        case .newTraining: return "graduationcap"
        }
    }
    static let drawer: [Self] = [.home, .newFinding, .findings, .companies, .memory, .documentChecklist, .documents, .visits, .statistics, .training, .reports, .reportArchive, .notifications]
    static let quickAdd: [Self] = [.newFinding, .newDocument, .newVisit, .newTraining]
}

enum NovaOverlay: String, CaseIterable { case drawer, quickAdd }

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
        available.contains(destination) && available.contains(destination.tab.root)
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
