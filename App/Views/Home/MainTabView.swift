import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuotaAlert = false
    @State private var showPaywall = false

    var body: some View {
        RDAdaptiveContainer { _ in
            ZStack {
                Color.rdPaper

                switch app.activeTab {
                case .home:     HomeView()
                case .analyses: HistoryView()
                case .reports:  ReportView()
                case .profile:  ProfileView()
                }

                if Self.isUITestLaunch {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("main_tab.\(app.activeTab.rawValue)")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RDTabBar(active: $app.activeTab) {
                    Task {
                        await handleQuickScanTap()
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
        .background(Color.rdPaper.ignoresSafeArea())
        .alert(RDLocalization.string("analysis.main.tab.view.ucretsiz.hak.doldu.02b7d919", table: .analysis, fallback: "Ücretsiz hak doldu"), isPresented: $showQuotaAlert) {
            Button(RDLocalization.string("analysis.main.tab.view.yukselt.a7a8cbd7", table: .analysis, fallback: "Yükselt")) {
                PaywallEventService.shared.beginEntry(
                    at: .quickScanQuotaAlert,
                    currentTier: app.currentTier,
                    targetTier: .plus
                )
                showPaywall = true
            }
            Button(RDLocalization.string("analysis.main.tab.view.tamam.ce1433e3", table: .analysis, fallback: "Tamam"), role: .cancel) {}
        } message: {
            Text(RDLocalization.string("analysis.main.tab.view.gunde.1.ucretsiz.analiz.hakkinizi.kullandiniz.pl.c4387499", table: .analysis, fallback: "Günde 1 ücretsiz analiz hakkınızı kullandınız. Plus veya Pro ile devam edebilirsiniz."))
        }
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(
                onClose: { showPaywall = false },
                onSubscribe: {
                    showPaywall = false
                    Task { await app.refreshPlanState() }
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    private func handleQuickScanTap() async {
        if !app.currentTier.isPaid {
            do {
                let usage = try await AnalysisService.shared.dailyQuotaUsage()
                if usage.isExhausted {
                    showQuotaAlert = true
                    return
                }
            } catch {
                // Kota kontrolü geçici olarak alınamazsa HomeView kendi korumasını yine çalıştırır.
            }
        }
        app.activeTab = .home
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            app.requestQuickScan(source: .chooser)
        }
    }

    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    private static var isUITestLaunch: Bool {
        #if DEBUG
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
        #else
        false
        #endif
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
