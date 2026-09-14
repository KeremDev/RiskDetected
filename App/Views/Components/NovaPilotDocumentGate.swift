import SwiftUI

/// The Evrak Takibi surface. Obligations belong to one company, so the page
/// works on one company at a time and says which one it is reading.
struct NovaPilotDocumentGate: View {
    let identity: NovaSessionIdentity
    let scope: NovaPersonnelScope?
    let canWrite: Bool
    let select: (UUID?) -> Void
    let currentScope: () -> NovaPersonnelScope?
    let onBack: () -> Void
    let onCompanies: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var company: UUID?
    @State private var loadFailed = false

    private var service: NovaDocumentTrackingService { .live(currentScope: currentScope) }
    private var selected: NovaAnalysisCompanyOption? { companies.first { $0.id == company } }

    var body: some View {
        Group {
            if let company, selected != nil {
                NovaDocumentTrackingScreen(client: client(company), onBack: onBack, canWrite: canWrite,
                    companyName: selected?.name)
                    .id(company)
                    .safeAreaInset(edge: .top) { switcher }
            } else {
                placeholder
            }
        }
        .task { await load() }
    }

    /// Which company the page is reading, and the one control that changes it.
    @ViewBuilder private var switcher: some View {
        if companies.count > 1 {
            Menu {
                ForEach(companies) { option in
                    Button(option.name) { company = option.id; select(option.id) }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "building.2").font(.system(size: 12, weight: .semibold))
                    NovaText(text: selected?.name ?? "", style: .meta)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
                .overlay(Capsule().strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 6)
            }.accessibilityIdentifier("document.tracking.company")
        }
    }

    private var placeholder: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        NovaBackButton { onBack() }
                        NovaText(text: NovaDestination.documentChecklist.title, style: .screenTitle)
                        Spacer(minLength: 0)
                    }
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            NovaText(text: loadFailed
                                ? RDLocalization.string("localizable.nova.document.company.failed", table: .localizable,
                                    fallback: "Firma listesi alınamadı. Tekrar deneyin.")
                                : companies.isEmpty
                                    ? RDLocalization.string("localizable.nova.document.company.empty", table: .localizable,
                                        fallback: "Evrak takibi için önce bir firma ekleyin.")
                                    : RDLocalization.string("localizable.nova.document.loading", table: .localizable,
                                        fallback: "Evrak takibi yükleniyor…"), style: .metaQuiet)
                            if companies.isEmpty && !loadFailed {
                                NovaButton(label: NovaDestination.companies.title, symbol: "building.2",
                                    variant: .surface) { onCompanies() }
                                    .accessibilityIdentifier("document.tracking.companies")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private func load() async {
        do {
            companies = try await NovaAnalysisWorkspace.companyOptions(identity: identity)
            loadFailed = false
        } catch {
            loadFailed = true
            return
        }
        // The workspace already has a company in scope; read that one rather
        // than making the expert choose again.
        if let current = scope?.companyID, companies.contains(where: { $0.id == current }) {
            company = current
        } else if let first = companies.first?.id {
            company = first
            select(first)
        }
    }

    /// Selecting a company runs the workspace availability check again, so the
    /// scope arrives a moment later. Waiting for it is waiting for a real
    /// verification, not working around one.
    private func waitForScope(_ target: UUID) async throws -> NovaPersonnelScope {
        if let ready = currentScope(), ready.companyID == target { return ready }
        select(target)
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let ready = currentScope(), ready.companyID == target { return ready }
        }
        throw NovaDocumentFailure.denied
    }

    private func client(_ target: UUID) -> NovaDocumentTrackingClient {
        func scoped() async throws -> NovaPersonnelScope { try await waitForScope(target) }
        return .init(
            load: { try await service.board(try await scoped()) },
            kinds: { try await service.kinds(try await scoped()) },
            workplaces: { try await service.workplaces(try await scoped()) },
            add: { draft in try await service.add(try await scoped(), draft: draft) },
            update: { entry, draft in try await service.update(try await scoped(), obligation: entry, draft: draft) },
            archive: { entry in try await service.archive(try await scoped(), obligation: entry) },
            recordCopy: { entry, draft in
                try await service.recordCopy(try await scoped(), obligation: entry, draft: draft)
            },
            removeCopy: { entry, copy in
                try await service.removeCopy(try await scoped(), obligation: entry, copy: copy)
            })
    }
}
