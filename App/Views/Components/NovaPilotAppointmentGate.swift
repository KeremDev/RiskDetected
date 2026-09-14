import SwiftUI

/// The Atama ve Temsilciler surface: who holds a safety role, in which scope,
/// and on what basis.
struct NovaPilotAppointmentGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaAppointmentService { .live() }

    var body: some View {
        NovaAppointmentScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride,
            management: { company, record in AnyView(NovaModuleEditor(identity: identity, module: "appointment", company: company, record: record)) })
    }

    private var client: NovaAppointmentClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { appointment in try await service.detail(identity, appointment: appointment) },
            record: { company, draft in try await service.record(identity, company: company, draft: draft) },
            end: { company, draft in try await service.end(identity, company: company, draft: draft) })
    }
}
