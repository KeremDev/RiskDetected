import SwiftUI

/// The Tatbikatlar surface: drills rehearsing a pinned version of an emergency
/// plan, with the people who were there frozen as they were named.
struct NovaPilotDrillGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaDrillService { .live() }
    private var fileService: NovaFileLibraryService { .live() }

    @State private var legacy = false
    var body: some View {
        if legacy {
            legacyScreen
        } else {
            VStack(spacing: 0) {
                NovaPilotProcessGate(identity: identity, kind: "completed_drill", initialCompany: initialCompany, canWrite: canWrite, onBack: onBack)
                Button(RDLocalization.string("localizable.nova.pilot.drill.gate.onceki.tatbikat.kayitlari.3664c32c", table: .localizable, fallback: "Önceki tatbikat kayıtları")) { legacy = true }
                    .font(NovaFont.font(.meta)).padding(8)
            }
        }
    }
    private var legacyScreen: some View {
        NovaDrillScreen(client: client, onBack: { legacy = false }, canWrite: false,
            initialCompany: initialCompany, headingOverride: headingOverride,
            management: { company, record in AnyView(NovaModuleEditor(identity: identity, module: "drill", company: company, record: record, fileClient: fileClient)) })
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

    private var client: NovaDrillClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { drill in try await service.detail(identity, drill: drill) },
            plan: { company, draft in try await service.plan(identity, company: company, draft: draft) },
            record: { company, draft in try await service.record(identity, company: company, draft: draft) },
            cancel: { company, drill, reason in
                try await service.cancel(identity, company: company, drill: drill, reason: reason)
            })
    }
}
