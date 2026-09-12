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

    init() {
        let args = Set(ProcessInfo.processInfo.arguments)
        var initial = NovaNavigationState(epoch: "synthetic-a", available: args.contains("--locked") ? [] : Set(NovaDestination.allCases))
        if args.contains("--stack") {
            initial.apply(.navigate(.memory), from: "synthetic-a")
            initial.apply(.navigate(.documents), from: "synthetic-a")
        }
        _navigation = State(initialValue: initial)
    }

    var body: some View {
        let fontsOK = Set(NovaTypeToken.allCases.map { $0.spec.fontName }).allSatisfy { UIFont(name: $0, size: 15) != nil }
        VStack(spacing: 0) {
            NovaExpertShell(navigation: $navigation, userName: "Örnek Uzman", hasUnread: true) { destination in
                HarnessDestination(destination: destination)
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
