import SwiftUI

/// The KKD Zimmetleri surface: what was handed to a person, and what came back.
struct NovaPilotPPEGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaPPEService { .live() }

    var body: some View {
        NovaPPEScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride)
    }

    private var client: NovaPPEClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
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
