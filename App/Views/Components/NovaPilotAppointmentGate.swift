import SwiftUI

/// The Atama ve Temsilciler surface: who holds a safety role, in which scope,
/// and on what basis.
struct NovaPilotAppointmentGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var initialRecordID: UUID?
    var headingOverride: String?
    var startInAddMode = false
    let onBack: () -> Void

    private var service: NovaAppointmentService { .live() }
    private var fileService: NovaFileLibraryService { .live() }

    var body: some View {
        NovaAppointmentScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, initialRecordID: initialRecordID,
            headingOverride: headingOverride, startInAddMode: startInAddMode,
            management: { company, record in AnyView(NovaModuleEditor(identity: identity, module: "appointment", company: company, record: record, fileClient: fileClient)) })
    }

    private var client: NovaAppointmentClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { appointment in try await service.detail(identity, appointment: appointment) },
            record: { company, draft in try await service.record(identity, company: company, draft: draft) },
            end: { company, draft in try await service.end(identity, company: company, draft: draft) },
            fileClient: fileClient)
    }

    private var fileClient: NovaFileLibraryClient {
        .init(
            catalogue: { try await fileService.catalogue(identity) },
            library: { request in try await fileService.library(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            file: { company, draft, data in try await fileService.file(identity, company: company, draft: draft, data: data) },
            rename: { entry, title, category, note in
                try await fileService.rename(identity, entry: entry, title: title, category: category, note: note) },
            archive: { entry in try await fileService.archive(identity, entry: entry) },
            cancel: { entry in try await fileService.cancel(identity, entry: entry) },
            recheck: { entry in try await fileService.recheck(identity, entry: entry) },
            contents: { entry in try await fileService.contents(identity, entry: entry) },
            download: { bucket, path in try await fileService.download(identity, bucket: bucket, path: path) })
    }
}
