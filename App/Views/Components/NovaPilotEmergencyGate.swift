import SwiftUI

/// The Acil Durum Planları surface: the versioned plan and the team frozen into
/// each version.
struct NovaPilotEmergencyGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaEmergencyPlanService { .live() }

    var body: some View {
        NovaEmergencyPlanScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride,
            management: { company, record in AnyView(NovaModuleEditor(identity: identity, module: "emergency_plan", company: company, record: record)) })
    }

    private var client: NovaEmergencyClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { plan in try await service.detail(identity, plan: plan) },
            publish: { company, draft in try await service.publish(identity, company: company, draft: draft) })
    }
}
