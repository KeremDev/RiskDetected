import SwiftUI
import CryptoKit

/// The Kontrol Listeleri surface: the expert's own question lists, and the runs
/// filled against a pinned version of one.
struct NovaPilotChecklistGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaChecklistService { .live() }

    var body: some View {
        NovaChecklistScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride)
    }

    /// The run detail and write replies leave the company name out. Without it
    /// a company run reads as a standalone one and a failing answer cannot
    /// open the company's nonconformity record, so fill it in here.
    private func named(_ run: NovaChecklistRun) async -> NovaChecklistRun {
        guard let company = run.companyID, run.companyName?.isEmpty ?? true else { return run }
        var named = run
        named.companyName = await NovaChecklistCompanyNames.shared.name(of: company, identity: identity)
        return named
    }

    private func named(_ run: NovaChecklistRun?) async -> NovaChecklistRun? {
        guard let run else { return nil }
        return await named(run)
    }

    private var client: NovaChecklistClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            library: { search, sector, kind, offset in
                try await service.library(identity, search: search, sector: sector, kind: kind, offset: offset)
            },
            templateDetail: { template in try await service.templateDetail(identity, template: template) },
            templates: { company in try await service.templates(identity, company: company) },
            assignments: { company in try await service.assignments(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { run in try await named(service.detail(identity, run: run)) },
            startRun: { company, workplace, template, day, area, equipment, document in
                try await named(service.startRun(identity, company: company, workplace: workplace,
                    template: template, startedOn: day, areaLabel: area,
                    equipmentLabel: equipment, documentNumber: document))
            },
            answer: { company, draft in
                do { return try await named(service.recordAnswer(identity, company: company, draft: draft)) }
                catch NovaChecklistFailure.unavailable {
                    try NovaChecklistOfflineQueue.shared.enqueue(identity, company: company, draft: draft)
                    return nil
                }
            },
            uploadEvidence: { company, attachment in
                var draft = NovaFileDraft()
                draft.title = attachment.title
                draft.category = "inspection_report"
                draft.tags = RDLocalization.string("localizable.nova.pilot.checklist.gate.kontrol.listesi.kanit.e374f84d", table: .localizable, fallback: "kontrol listesi, kanıt")
                draft.fileName = attachment.filename
                draft.fileExtension = (attachment.filename as NSString).pathExtension.lowercased()
                draft.bytes = attachment.data.count
                draft.sha256 = SHA256.hash(data: attachment.data)
                    .map { String(format: "%02x", $0) }.joined()
                let entry = try await NovaFileLibraryService.live().file(
                    identity, company: company, draft: draft, data: attachment.data)
                guard entry.state.isFiled, let asset = entry.assetID else {
                    throw NovaFileFailure.inspectionUnavailable
                }
                return asset
            },
            submit: { company, run, revision in
                try await named(service.submitRun(identity, company: company, run: run, expectedRevision: revision))
            },
            cancel: { company, run, revision in
                try await named(service.cancelRun(identity, company: company, run: run, expectedRevision: revision))
            },
            revise: { company, run, revision, day in
                try await named(service.reviseRun(identity, company: company, run: run,
                                                  expectedRevision: revision, startedOn: day))
            },
            draftTemplate: { company, title in
                try await service.draftTemplate(identity, company: company, title: title)
            },
            setItem: { company, code, version, revision, item, prompt, allowsNA, position in
                try await service.setItem(identity, company: company, template: code, version: version,
                                          itemCode: item, prompt: prompt,
                                          allowsNotApplicable: allowsNA, position: position,
                                          expectedRevision: revision)
            },
            copyItems: { company, code, version, revision, items in
                try await service.copyItems(identity, company: company, template: code,
                                            version: version, expectedRevision: revision, items: items)
            },
            reorderItems: { company, code, version, revision, itemCodes in
                try await service.reorderItems(identity, company: company, template: code,
                                               version: version, expectedRevision: revision,
                                               itemCodes: itemCodes)
            },
            removeItem: { company, code, version, revision, item in
                try await service.removeItem(identity, company: company, template: code,
                                             version: version, expectedRevision: revision,
                                             itemCode: item)
            },
            publishTemplate: { company, code, version, revision, note in
                try await service.publishTemplate(identity, company: company, template: code,
                    version: version, expectedRevision: revision, note: note)
            },
            copyTemplate: { company, template, title in
                try await service.copyTemplate(identity, company: company, template: template, title: title)
            },
            assignTemplate: { company, workplace, template in
                try await service.assignTemplate(identity, company: company, workplace: workplace, template: template)
            },
            deactivateAssignment: { company, assignment in
                try await service.deactivateAssignment(identity, company: company, assignment: assignment)
            },
            pendingAnswers: {
                (NovaChecklistOfflineQueue.shared.count(identity),
                 NovaChecklistOfflineQueue.shared.conflictCount(identity))
            },
            syncPendingAnswers: {
                _ = await NovaChecklistOfflineQueue.shared.flush(identity) { company, draft in
                    try await service.recordAnswer(identity, company: company, draft: draft)
                }
                return (NovaChecklistOfflineQueue.shared.count(identity),
                        NovaChecklistOfflineQueue.shared.conflictCount(identity))
            })
    }
}

/// Company names for checklist runs, loaded once per account and reloaded when
/// a run points at a company not seen yet.
private actor NovaChecklistCompanyNames {
    static let shared = NovaChecklistCompanyNames()
    private var names: [UUID: String] = [:]
    private var owner: NovaSessionIdentity?

    func name(of company: UUID, identity: NovaSessionIdentity) async -> String? {
        if owner != identity { names = [:]; owner = identity }
        if let name = names[company] { return name }
        guard let options = try? await NovaAnalysisWorkspace.companyOptions(identity: identity) else { return nil }
        guard owner == identity else { return nil }
        for option in options { names[option.id] = option.name }
        return names[company]
    }
}
