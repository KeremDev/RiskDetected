import SwiftUI

/// The Periyodik Kontroller surface. The page answers the whole account in one
/// read and narrows to one company only when the expert asks it to.
struct NovaPilotEquipmentGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    /// Opened from a company page: the module starts on that company.
    var initialCompany: UUID?
    var headingOverride: String?
    /// Opened from the company page's own "Ekipman ekle" action.
    var startInAddMode = false
    /// Opened from the company page's own "Kontrol ekle" action.
    var startInInspectionMode = false
    let onBack: () -> Void

    private var service: NovaEquipmentCheckService { .live() }
    private var files: NovaFileLibraryService { .live() }

    var body: some View {
        NovaEquipmentCheckScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, startInAddMode: startInAddMode,
            startInInspectionMode: startInInspectionMode, headingOverride: headingOverride)
    }

    private var client: NovaEquipmentCheckClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { equipment in try await service.detail(identity, equipment: equipment) },
            register: { company, draft in try await service.register(identity, company: company, draft: draft) },
            update: { equipment, draft in try await service.update(identity, equipment: equipment, draft: draft) },
            archive: { equipment in try await service.archive(identity, equipment: equipment) },
            setRule: { company, draft in try await service.setRule(identity, company: company, draft: draft) },
            recordInspection: { equipment, draft in
                try await service.recordInspection(identity, equipment: equipment, draft: draft)
            },
            updateInspection: { equipment, inspection, draft in
                try await service.updateInspection(identity, equipment: equipment,
                                                   inspection: inspection, draft: draft)
            },
            // The reports the archive already holds for this company, so an
            // inspection can point at a filed document instead of carrying a
            // second copy of one. Only files that were actually cleared appear.
            filedReports: { company in
                let page = try await files.library(identity, query: .init(
                    state: NovaFileState.promoted.rawValue, company: company,
                    category: "inspection_report", limit: 50))
                return page.rows.filter(\.canDownload)
            },
            fileClient: fileClient)
    }

    private var fileClient: NovaFileLibraryClient {
        .init(
            catalogue: { try await files.catalogue(identity) },
            library: { request in try await files.library(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            file: { company, draft, data in try await files.file(identity, company: company, draft: draft, data: data) },
            rename: { entry, title, category, note in
                try await files.rename(identity, entry: entry, title: title, category: category, note: note) },
            archive: { entry in try await files.archive(identity, entry: entry) },
            cancel: { entry in try await files.cancel(identity, entry: entry) },
            recheck: { entry in try await files.recheck(identity, entry: entry) },
            contents: { entry in try await files.contents(identity, entry: entry) },
            download: { bucket, path in try await files.download(identity, bucket: bucket, path: path) })
    }
}
