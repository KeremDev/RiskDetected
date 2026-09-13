import SwiftUI

/// The legacy management view remains the fallback when rollout/RPC/auth is unavailable.
struct NovaCompanyManagementGate<Fallback: View>: View {
    let onClose: () -> Void
    @ViewBuilder let fallback: () -> Fallback
    @StateObject private var controller = NovaWorkspaceController()
    @State private var legacyRequested = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if controller.resolving {
                NovaPageSurface { VStack(spacing: 18) { ProgressView(); NovaText(text: "Firma erişimi doğrulanıyor…"); NovaButton(label: "Kapat", symbol: "xmark", variant: .surface, action: onClose) }.padding(18) }
            } else if controller.isAvailable && !legacyRequested {
                NavigationStack {
                    if let scope = controller.scope {
                        NovaCompanyWorkspace(scope: scope, companyName: controller.capability?.company_name ?? "Firma", canWrite: controller.canWrite,
                            personnel: controller.personnelClient, directory: controller.directoryClient, onBack: { controller.select(nil) })
                    } else {
                        VStack(spacing: 0) {
                            NovaCompanyDestination(host: Binding(get: { controller.host }, set: { _ in }),
                                loadCompanies: { try await loadNovaOwnedCompanies(includeArchived: $0) }, includeArchived: true, onSelect: controller.select, onBack: onClose)
                            NovaButton(label: "Firma ekle / düzenle", symbol: "building.2", variant: .surface) { legacyRequested = true }.padding(18)
                        }.background(NovaColorToken.canvas.color(in: .light))
                    }
                }.id(controller.host.navigation.epoch)
                .preferredColorScheme(.light)
            } else {
                VStack(spacing: 0) {
                    if legacyRequested && controller.isAvailable {
                        NovaButton(label: "Personel ve işyeri yönetimine dön", symbol: "chevron.left", variant: .surface) { legacyRequested = false; controller.select(nil) }.padding(12)
                    }
                    fallback()
                }
            }
        }
        .task { await controller.observe() }
        .onChange(of: scenePhase) { phase in if phase == .active { controller.refresh() } }
        .onChange(of: controller.host.identity) { _ in legacyRequested = false }
    }
}

struct NovaCompanyWorkspace: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let canWrite: Bool
    let personnel: NovaPersonnelClient
    let directory: NovaDirectoryClient
    let onBack: () -> Void
    @State private var route: Route = .hub
    private enum Route { case hub, personnel, directory(NovaDirectoryKind) }
    var body: some View {
        NovaPageSurface {
            switch route {
            case .personnel:
                NovaPersonnelDestination(scope: scope, companyName: companyName, client: personnel, onBack: { route = .hub }, directory: directory, canWrite: canWrite)
            case .directory(let kind):
                NovaDirectoryDestination(scope: scope, kind: kind, client: directory, onBack: { route = .hub }, canWrite: canWrite)
            case .hub:
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Button(action: onBack) { NovaIcon(symbol: "chevron.left", size: 24).frame(width: 44, height: 44) }; NovaText(text: companyName, style: .screenTitle) }
                        if !canWrite { NovaCard(padding: 16) { Label("Salt okunur · kayıtlarınız korunuyor", systemImage: "lock"); NovaText(text: "Yeni kayıt ve düzenleme şu anda kullanılamıyor.", style: .metaQuiet) } }
                        entry("Personeller", "person.2") { route = .personnel }
                        ForEach([NovaDirectoryKind.workplaces, .departments, .jobs, .contractors], id: \.self) { kind in
                            entry(kind.title, kind.symbol) { route = .directory(kind) }
                        }
                    }.padding(18)
                }
            }
        }.navigationBarBackButtonHidden(true)
    }
    private func entry(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { NovaCard(padding: 20) { HStack { NovaIcon(symbol: icon, size: 24); NovaText(text: title, style: .cardTitle); Spacer(); NovaIcon(symbol: "chevron.right", size: 18) } } }.buttonStyle(.plain)
    }
}
