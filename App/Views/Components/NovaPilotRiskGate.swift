import SwiftUI

/// The Risk Değerlendirmesi surface. The page answers the whole account in one
/// read and narrows to one company only when the expert asks it to.
struct NovaPilotRiskGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    /// Opened from a company page: the module starts on that company.
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaRiskAssessmentService { .live() }

    var body: some View {
        NovaRiskScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride)
    }

    private var client: NovaRiskClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { assessment in try await service.detail(identity, assessment: assessment) },
            open: { company, workplace in try await service.open(identity, company: company, workplace: workplace) },
            draft: { company, draft in try await service.draft(identity, company: company, draft: draft) },
            finalize: { company, draft in try await service.finalize(identity, company: company, draft: draft) })
    }
}
