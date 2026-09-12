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
    @State private var navigation: NovaNavigationState
    @State private var staleAction: (() -> Void)?
    @State private var notices = [
        NovaNotice(id: "overdue", title: "Termini geçen aksiyonlar", detail: "Geciken düzeltmeleri önceliklendirerek inceleyin.", count: 1, symbol: "risk", tone: .statusDangerInk),
        NovaNotice(id: "active", title: "Aktif uygunsuzluklar", detail: "Sorumluluğunuzdaki firmalarda halen açık bulunan kayıtlar.", count: 1, symbol: "bell.fill", tone: .statusInfoInk)
    ]

    init() {
        let args = Set(ProcessInfo.processInfo.arguments)
        var initial = NovaNavigationState(epoch: "synthetic-a", available: args.contains("--locked") ? [] : Set(NovaDestination.allCases))
        if args.contains("--stack") {
            initial.apply(.navigate(.memory), from: "synthetic-a")
            initial.apply(.navigate(.documents), from: "synthetic-a")
        }
        if args.contains("--companies") { initial.apply(.select(.companies), from: "synthetic-a") }
        if args.contains("--drawer") { initial.apply(.open(.drawer), from: "synthetic-a") }
        if args.contains("--add") { initial.apply(.open(.quickAdd), from: "synthetic-a") }
        if args.contains("--notices") { initial.apply(.open(.notifications), from: "synthetic-a") }
        _navigation = State(initialValue: initial)
    }

    var body: some View {
        let fontsOK = Set(NovaTypeToken.allCases.map { $0.spec.fontName }).allSatisfy { UIFont(name: $0, size: 15) != nil }
        VStack(spacing: 0) {
            NovaExpertShell(navigation: $navigation, userName: "Kerem Kaya", hasUnread: notices.contains(where: \.unread),
                notificationItems: notices, connectionLabel: "Çevrimiçi",
                onReadAll: { notices = notices.map { var n = $0; n.unread = false; return n } },
                onClearNotifications: { notices = [] },
                onLogout: { navigation.resetAccount(to: "signed-out-preview", available: []) }) { destination in
                if args.contains("--design"), destination == .home {
                    NovaDashboardScreen(data: Self.dashboard, onNavigate: navigate,
                        onPhoto: { navigate(.newFinding) }, onAssistant: { navigate(.newFinding) }, onFinding: { _ in navigate(.findings) })
                } else if args.contains("--design"), destination == .companies {
                    NovaCompaniesScreen(companies: [NovaCompanyItem(id: "fixture-company", name: "Koza Altın A.Ş", detail: "Kaymaz Mah. · Maden · Çok tehlikeli")],
                        onSelect: { _ in navigate(.memory) }, onBack: { navigate(.home) }, onRetry: {})
                } else { HarnessDestination(destination: destination) }
            }
            .frame(maxWidth: args.contains("--compact") ? 320 : .infinity)
            .environment(\.dynamicTypeSize, args.contains("--ax3") ? .accessibility3 : .large)
            .preferredColorScheme(args.contains("--dark") ? .dark : .light)
            if args.contains("--qa-toolbar") {
                VStack(spacing: 4) {
                    Text("QA · \(navigation.epoch) · \(navigation.selected.rawValue) · \(navigation.current.rawValue) · fonts=\(fontsOK ? "ok" : "FAIL")")
                        .font(.system(size: 10)).accessibilityIdentifier("qa.state")
                    HStack {
                        Button("Yakalama") {
                            let captured = navigation.epoch
                            staleAction = { navigation.apply(.navigate(.notifications), from: captured) }
                        }.accessibilityIdentifier("qa.capture")
                        Button("Hesap reset") { navigation.resetAccount(to: "synthetic-b", available: []) }
                            .accessibilityIdentifier("qa.reset")
                        Button("Eski işlem") { staleAction?() }.accessibilityIdentifier("qa.replay")
                        Button("İzin kaldır") { navigation.updateAvailability([], from: navigation.epoch) }
                            .accessibilityIdentifier("qa.revoke")
                    }.font(.system(size: 11)).buttonStyle(.bordered)
                }.padding(4).background(.yellow.opacity(0.15))
            }
        }
    }

    private func navigate(_ destination: NovaDestination) { navigation.apply(.navigate(destination), from: navigation.epoch) }
    private static let dashboard = NovaDashboardData(firstName: "Kerem", openCount: 1, metrics: [
        NovaMetricItem(id: "total", value: "1", label: "Toplam Uygunsuzluk", footer: "+1 bu ay", symbol: "bookmark", tone: .statusInfoDot, destination: .findings),
        NovaMetricItem(id: "open", value: "1", label: "Açık Uygunsuzluk", footer: "1 gecikmiş", symbol: "exclamationmark.triangle", tone: .statusDangerDot, destination: .findings),
        NovaMetricItem(id: "companies", value: "1", label: "Firma", footer: "Atanmış firma", symbol: "building.2", tone: .statusInfoDot, destination: .companies),
        NovaMetricItem(id: "visits", value: "1", label: "Ziyaret Sayısı", footer: "1 bu ay", symbol: "mappin", tone: .statusWarningDot, destination: .visits),
        NovaMetricItem(id: "training", value: "0", label: "Eğitim Süresi Geçen", footer: "personel", symbol: "clock", tone: .statusDangerDot, destination: .training)
    ], activity: "Yeni firma atandı · Koza Altın A.Ş · Ahmet Bel · Uzman atandı", trainingMessage: "Yaklaşan veya geçmiş eğitim uyarısı yok", recentFindings: [NovaRecentFinding(id: "fixture-finding", companyName: "Koza Altın…")])
}

private struct HarnessDestination: View {
    let destination: NovaDestination
    @State private var count = 0
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NovaText(text: destination.title, style: .screenTitle)
                    .accessibilityIdentifier("qa.content.\(destination.rawValue)")
                NovaText(text: "Sentetik test ekranı. Canlı veri veya işlem yok.", style: .meta)
                NovaButton(label: "Sayaç \(count)", action: { count += 1 })
                    .accessibilityIdentifier("qa.counter")
            }.padding(20)
        }
    }
}
