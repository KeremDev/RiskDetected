import SwiftUI
import UIKit

#if !targetEnvironment(simulator)
#error("The synthetic shell harness must never build for a physical device or store archive")
#endif

/// Separate test executable: no production root, app services, credentials, persistence or SDKs.
@main struct ShellHarnessApp: App {
    var body: some Scene { WindowGroup { ShellHarnessRoot() } }
}

struct ShellHarnessRoot: View {
    private let args = Set(ProcessInfo.processInfo.arguments)
    @State private var sessionHost: NovaSessionHost
    @State private var staleAction: (() -> Void)?
    @State private var delayedResponse: (() -> Void)?
    @State private var noticeSnapshot: NovaScopedValue<[NovaNotice]>?
    @State private var companyRequests = 0
    @StateObject private var personnel = PersonnelHarness()
    private static let fixtureNotices = [
        NovaNotice(id: "overdue", title: "Termini geçen aksiyonlar", detail: "Geciken düzeltmeleri önceliklendirerek inceleyin.", badge: "1 gün gecikti", symbol: "risk", tone: .statusDangerInk),
        NovaNotice(id: "active", title: "Aktif uygunsuzluklar", detail: "Sorumluluğunuzdaki firmalarda halen açık bulunan kayıtlar.", badge: "1 açık kayıt", symbol: "bell.fill", tone: .statusInfoInk)
    ]

    init() {
        let args = Set(ProcessInfo.processInfo.arguments)
        var initial = Self.readyHost(identity: Self.actorA, enabled: args.contains("--locked") ? [] : Set(NovaDestination.allCases))
        if args.contains("--stack") {
            initial.apply(.navigate(.memory), from: initial.navigation.epoch)
            initial.apply(.navigate(.documents), from: initial.navigation.epoch)
        }
        if args.contains("--companies") { initial.apply(.select(.companies), from: initial.navigation.epoch) }
        if args.contains("--drawer") { initial.apply(.open(.drawer), from: initial.navigation.epoch) }
        if args.contains("--add") { initial.apply(.open(.quickAdd), from: initial.navigation.epoch) }
        if args.contains("--notices") { initial.apply(.open(.notifications), from: initial.navigation.epoch) }
        _sessionHost = State(initialValue: initial)
        _noticeSnapshot = State(initialValue: initial.scope(Self.fixtureNotices, from: initial.navigation.epoch))
    }

    var body: some View {
        let fontsOK = Set(NovaTypeToken.allCases.map { $0.spec.fontName }).allSatisfy { UIFont(name: $0, size: 15) != nil }
        let renderedEpoch = navigation.epoch
        let navigate: (NovaDestination) -> Void = { sessionHost.apply(.navigate($0), from: renderedEpoch) }
        VStack(spacing: 0) {
            if sessionHost.phase == .ready {
            NovaExpertShell(navigation: navigationBinding, userName: sessionHost.identity == Self.actorA ? "Kerem Kaya" : "Örnek B", hasUnread: notices.contains(where: \.unread),
                notificationItems: notices, connectionLabel: "Çevrimiçi",
                onReadAll: { noticeSnapshot = sessionHost.scope(notices.map { var n = $0; n.unread = false; return n }, from: navigation.epoch) },
                onClearNotifications: { noticeSnapshot = sessionHost.scope([], from: navigation.epoch) },
                onLogout: { sessionHost.adopt(nil) }) { destination in
                if args.contains("--directory"), destination == .home, let identity = sessionHost.identity {
                    NovaDirectoryDestination(scope: .init(ownerID: identity.userID, sessionID: identity.sessionID,
                        companyID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, epoch: navigation.epoch),
                        kind: args.contains("--directory-departments") ? .departments : .engagements, client: personnel.directoryFixture, onBack: {})
                } else if args.contains("--personnel"), destination == .home, let identity = sessionHost.identity {
                    NovaPersonnelDestination(scope: .init(ownerID: identity.userID, sessionID: identity.sessionID,
                        companyID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, epoch: navigation.epoch),
                        companyName: "Sentetik firma", client: personnel.client, onBack: {}, directory: personnel.directory, canWrite: !args.contains("--personnel-readonly"))
                } else if args.contains("--company-loader"), destination == .companies {
                    NovaCompanyDestination(host: $sessionHost, loadCompanies: { _ in
                        companyRequests += 1
                        let owner = sessionHost.identity!.userID
                        if args.contains("--company-loader-failure"), companyRequests == 1 {
                            throw NSError(domain: "synthetic-private-body-must-not-appear", code: 1)
                        }
                        // Deliberately uncooperative synthetic provider: the destination's
                        // post-await cancellation and current-host guards must still protect UI.
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        return [.init(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, ownerID: owner,
                            name: owner == Self.actorA.userID ? "Firma A" : "Firma B", detail: "Sentetik adres · Çok Tehlikeli", isArchived: false)]
                    }, onSelect: { _ in navigate(.memory) }, onBack: { navigate(.home) })
                } else if args.contains("--design"), destination == .home {
                    NovaDashboardScreen(data: Self.dashboard, onNavigate: navigate,
                        onPhoto: { navigate(.newFinding) }, onAssistant: { navigate(.newFinding) }, onFinding: { _ in navigate(.findings) })
                } else if args.contains("--design"), destination == .companies {
                    NovaCompaniesScreen(companies: [NovaCompanyItem(id: "fixture-company", name: "Koza Altın A.Ş", detail: "Kaymaz Mah. · Maden · Çok tehlikeli")],
                        onSelect: { _ in navigate(.memory) }, onBack: { navigate(.home) }, onRetry: {})
                } else {
                    // Pages own their back control (the shell has none); pushed pages get one, tab roots do not.
                    HarnessDestination(destination: destination,
                        onBack: (navigation.paths[navigation.selected] ?? []).last == destination
                            ? { sessionHost.apply(.back, from: renderedEpoch) } : nil)
                }
            }
            .frame(maxWidth: args.contains("--compact") ? 320 : .infinity)
            .environment(\.dynamicTypeSize, args.contains("--ax3") ? .accessibility3 : .large)
            .preferredColorScheme(args.contains("--dark") ? .dark : .light)
            } else {
                Text("QA · \(sessionHost.phase.rawValue)").accessibilityIdentifier("qa.host.unavailable")
            }
            if args.contains("--qa-toolbar") {
                VStack(spacing: 4) {
                    if args.contains("--directory") { Text("saves=\(personnel.directorySaves)").accessibilityIdentifier("qa.directory.saves") }
                    if args.contains("--company-loader") {
                        Button("Firma hesabını değiştir") {
                            sessionHost.adopt(Self.actorB)
                            resolveImmediately(Set(NovaDestination.allCases))
                            sessionHost.apply(.select(.companies), from: sessionHost.navigation.epoch)
                        }.accessibilityIdentifier("qa.company.switch")
                    }
                    Text("QA · \(sessionHost.identity == Self.actorA ? "synthetic-a" : "synthetic-b") · \(navigation.selected.rawValue) · \(navigation.current.rawValue) · fonts=\(fontsOK ? "ok" : "FAIL")")
                        .font(.system(size: 10)).accessibilityIdentifier("qa.state")
                    HStack {
                        Button("Yakalama") {
                            let captured = navigation.epoch
                            staleAction = { sessionHost.apply(.navigate(.notifications), from: captured) }
                        }.accessibilityIdentifier("qa.capture")
                        Button("Hesap reset") { sessionHost.adopt(Self.actorB); resolveImmediately([]) }
                            .accessibilityIdentifier("qa.reset")
                        Button("Eski işlem") { staleAction?() }.accessibilityIdentifier("qa.replay")
                        Button("İzin kaldır") { resolveImmediately([]) }
                            .accessibilityIdentifier("qa.revoke")
                    }.font(.system(size: 11)).buttonStyle(.bordered)
                    HStack {
                        Button("Yetki yenile") {
                            guard let ticket = sessionHost.beginAvailabilityRefresh() else { return }
                            delayedResponse = { sessionHost.resolve(ticket, ownerID: Self.actorA.userID, enabled: Set(NovaDestination.allCases)) }
                        }.accessibilityIdentifier("qa.host.refresh")
                        Button("Yanıtı getir") { delayedResponse?() }.accessibilityIdentifier("qa.host.deliver")
                    }.font(.system(size: 11)).buttonStyle(.bordered)
                }.padding(4).background(.yellow.opacity(0.15))
            }
        }
    }

    private var navigation: NovaNavigationState { sessionHost.navigation }
    private var notices: [NovaNotice] { sessionHost.value(from: noticeSnapshot) ?? [] }
    private var navigationBinding: Binding<NovaNavigationState> {
        let epoch = navigation.epoch
        return Binding(get: { sessionHost.navigation }, set: { sessionHost.acceptNavigation($0, from: epoch) })
    }
    private func resolveImmediately(_ enabled: Set<NovaDestination>) {
        guard let actor = sessionHost.identity, let ticket = sessionHost.beginAvailabilityRefresh() else { return }
        sessionHost.resolve(ticket, ownerID: actor.userID, enabled: enabled)
    }
    private static let actorA = NovaSessionIdentity(userID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, sessionID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
    private static let actorB = NovaSessionIdentity(userID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, sessionID: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!)
    private static func readyHost(identity: NovaSessionIdentity, enabled: Set<NovaDestination>) -> NovaSessionHost {
        var host = NovaSessionHost(implemented: Set(NovaDestination.allCases))
        host.adopt(identity)
        let ticket = host.beginAvailabilityRefresh()!
        host.resolve(ticket, ownerID: identity.userID, enabled: enabled)
        return host
    }
    private static let dashboard = NovaDashboardData(firstName: "Kerem", openCount: 1, metrics: [
        NovaMetricItem(id: "total", value: "1", label: "Toplam Uygunsuzluk", footer: "+1 bu ay", symbol: "bookmark", tone: .statusInfoDot, destination: .findings),
        NovaMetricItem(id: "open", value: "1", label: "Açık Uygunsuzluk", footer: "1 gecikmiş", symbol: "exclamationmark.triangle", tone: .statusDangerDot, destination: .findings),
        NovaMetricItem(id: "companies", value: "1", label: "Firma", footer: "Atanmış firma", symbol: "building.2", tone: .statusInfoDot, destination: .companies),
        NovaMetricItem(id: "visits", value: "1", label: "Ziyaret Sayısı", footer: "1 bu ay", symbol: "mappin", tone: .statusWarningDot, destination: .visits),
        NovaMetricItem(id: "training", value: "0", label: "Eğitim Süresi Geçen", footer: "personel", symbol: "clock", tone: .statusDangerDot, destination: .training)
    ], activity: "Yeni firma atandı · Koza Altın A.Ş · Ahmet Bel · Uzman atandı", trainingMessage: "Yaklaşan veya geçmiş eğitim uyarısı yok", recentAnalyses: [NovaRecentAnalysis(id: "fixture-analysis", title: "İskele çalışması", companyName: "Koza Altın A.Ş", createdOn: "24.09.2026")])
}

private struct HarnessDestination: View {
    let destination: NovaDestination
    var onBack: (() -> Void)?
    @State private var count = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    if let onBack { NovaBackButton(action: onBack).accessibilityIdentifier("nova.back") }
                    NovaIcon(symbol: destination.symbol, size: 22)
                        .foregroundStyle(NovaColorToken.accent.color(in: scheme))
                    NovaText(text: destination.title, style: .screenTitle)
                        .accessibilityIdentifier("qa.content.\(destination.rawValue)")
                }
                NovaCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        NovaText(text: "Sentetik test ekranı. Canlı veri veya işlem yok.", style: .meta)
                        NovaButton(label: "Sayaç \(count)", symbol: "plus", action: { count += 1 })
                            .accessibilityIdentifier("qa.counter")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("qa.card")
            }.padding(20)
        }
    }
}
