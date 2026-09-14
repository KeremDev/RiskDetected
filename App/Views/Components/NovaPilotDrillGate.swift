import SwiftUI

/// The Tatbikatlar surface: drills rehearsing a pinned version of an emergency
/// plan, with the people who were there frozen as they were named.
struct NovaPilotDrillGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaDrillService { .live() }

    var body: some View {
        NovaDrillScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride,
            management: { company, record in AnyView(NovaModuleEditor(identity: identity, module: "drill", company: company, record: record)) })
    }

    private var client: NovaDrillClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { drill in try await service.detail(identity, drill: drill) },
            plan: { company, draft in try await service.plan(identity, company: company, draft: draft) },
            record: { company, draft in try await service.record(identity, company: company, draft: draft) },
            cancel: { company, drill, reason in
                try await service.cancel(identity, company: company, drill: drill, reason: reason)
            })
    }
}
