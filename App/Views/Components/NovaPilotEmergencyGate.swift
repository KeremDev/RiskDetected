import SwiftUI

/// The Acil Durum Planları surface: the versioned plan and the team frozen into
/// each version.
struct NovaPilotEmergencyGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var initialRecordID: UUID?
    var headingOverride: String?
    var startInAddMode = false
    let onBack: () -> Void

    private var service: NovaEmergencyPlanService { .live() }
    private var fileService: NovaFileLibraryService { .live() }

    var body: some View {
        NovaEmergencyPlanScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, initialRecordID: initialRecordID,
            headingOverride: headingOverride, startInAddMode: startInAddMode,
            management: { company, record in AnyView(NovaModuleEditor(identity: identity, module: "emergency_plan", company: company, record: record, fileClient: fileClient)) })
    }

    private var client: NovaEmergencyClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { plan in try await service.detail(identity, plan: plan) },
            publish: { company, draft in try await service.publish(identity, company: company, draft: draft) },
            fileClient: fileClient,
            employees: { company, query, cursor in
                let scope = NovaPersonnelScope(ownerID: identity.userID, sessionID: identity.sessionID,
                    companyID: company, epoch: "emergency-team")
                let personnel = NovaPersonnelService.live(currentScope: { scope }).client
                return try await personnel.employees(scope, query, false, cursor)
            })
    }

    private var fileClient: NovaFileLibraryClient {
        .init(
            catalogue: { try await fileService.catalogue(identity) },
            library: { request in try await fileService.library(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            file: { company, draft, data in
                try await fileService.file(identity, company: company, draft: draft, data: data)
            },
            rename: { entry, title, category, note in
                try await fileService.rename(identity, entry: entry, title: title, category: category, note: note)
            },
            archive: { entry in try await fileService.archive(identity, entry: entry) },
            cancel: { entry in try await fileService.cancel(identity, entry: entry) },
            recheck: { entry in try await fileService.recheck(identity, entry: entry) },
            contents: { entry in try await fileService.contents(identity, entry: entry) },
            download: { bucket, path in try await fileService.download(identity, bucket: bucket, path: path) })
    }
}
