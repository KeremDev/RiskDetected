import SwiftUI

/// Composition root for the full KKD handover module. The design-system
/// screen owns presentation state; this gate supplies authenticated calls.
struct NovaPilotPPEGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    var startInAddMode = false
    let onBack: () -> Void

    private var service: NovaPPEService { .live() }

    var body: some View {
        NovaPPEScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride,
            startInAddMode: startInAddMode)
    }

    private var client: NovaPPEClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { query in try await service.board(identity, query: query) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { handover in try await service.detail(identity, handover: handover) },
            recordHandover: { company, draft in
                try await service.recordHandover(identity, company: company, draft: draft)
            },
            recordReturn: { company, draft in
                try await service.recordReturn(identity, company: company, draft: draft)
            },
            removeReturn: { company, handover, entry in
                try await service.removeReturn(identity, company: company, handover: handover, entry: entry)
            })
    }
}
