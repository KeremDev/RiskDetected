import SwiftUI

/// The Evrak Takibi surface. The page answers the whole account in one read and
/// narrows to one company only when the expert asks it to.
struct NovaPilotDocumentGate: View {
    let identity: NovaSessionIdentity
    let scope: NovaPersonnelScope?
    let canWrite: Bool
    let select: (UUID?) -> Void
    let currentScope: () -> NovaPersonnelScope?
    let onBack: () -> Void
    let onCompanies: () -> Void
    /// Opened from a company page: the tracker starts on that company, and on
    /// that heading's own document kinds when one was named.
    var initialCompany: UUID?
    var initialKinds: [String]?
    var headingOverride: String?

    private var service: NovaDocumentTrackingService { .live(currentScope: currentScope) }

    var body: some View {
        NovaFollowupScreen(identity: identity, initialCompany: initialCompany, canWrite: canWrite, onBack: onBack, legacy: { company in
            AnyView(NovaDocumentTrackingScreen(client: client, onBack: onBack, canWrite: false,
                initialCompany: company, initialKinds: initialKinds, headingOverride: "Önceki Evrak Kayıtları"))
        })
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

    /// Every write is scoped to the company the row itself names, so the page
    /// can hold rows from several companies without borrowing one scope.
    private func scoped(_ row: NovaDocumentObligation) async throws -> NovaPersonnelScope {
        guard let company = row.companyID else { throw NovaDocumentFailure.denied }
        return try await waitForScope(company)
    }

    private var client: NovaDocumentTrackingClient {
        .init(
            portfolio: { request in
                try await service.portfolio(identity, query: request.query, status: request.status,
                    company: request.company, kinds: request.kinds,
                    limit: request.limit, offset: request.offset)
            },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            kinds: { company in try await service.kinds(try await waitForScope(company)) },
            workplaces: { company in try await service.workplaces(try await waitForScope(company)) },
            add: { company, draft in try await service.add(try await waitForScope(company), draft: draft) },
            update: { row, draft in try await service.update(try await scoped(row), obligation: row, draft: draft) },
            archive: { row in try await service.archive(try await scoped(row), obligation: row) },
            recordCopy: { row, draft in
                try await service.recordCopy(try await scoped(row), obligation: row, draft: draft)
            },
            removeCopy: { row, copy in
                try await service.removeCopy(try await scoped(row), obligation: row, copy: copy)
            })
    }
}
