import SwiftUI

/// The Risk Değerlendirmesi surface. The page answers the whole account in one
/// read and narrows to one company only when the expert asks it to.
struct NovaPilotRiskGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    /// Opened from a company page: the module starts on that company.
    var initialCompany: UUID?
    var initialRecordID: UUID?
    var headingOverride: String?
    var showBackButton = true
    var startInAddMode = false
    var startWithWizard = false
    let onBack: () -> Void

    private var service: NovaRiskAssessmentService { .live() }
    private var files: NovaFileLibraryService { .live() }

    var body: some View {
        NovaRiskScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, initialRecordID: initialRecordID,
            headingOverride: headingOverride, showBackButton: showBackButton,
            startInAddMode: startInAddMode, startWithWizard: startWithWizard)
    }

    private var client: NovaRiskClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { assessment in try await service.detail(identity, assessment: assessment) },
            open: { company, workplace in try await service.open(identity, company: company, workplace: workplace) },
            draft: { company, draft in try await service.draft(identity, company: company, draft: draft) },
            finalize: { company, draft in try await service.finalize(identity, company: company, draft: draft) },
            cancelDraft: { company, row, version, reason in try await service.cancelDraft(identity, company: company, row: row, version: version, reason: reason) },
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
