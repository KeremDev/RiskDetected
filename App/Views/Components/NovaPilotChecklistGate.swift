import SwiftUI

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

    private var client: NovaChecklistClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            templates: { company in try await service.templates(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { run in try await service.detail(identity, run: run) },
            startRun: { company, workplace, template, day in
                try await service.startRun(identity, company: company, workplace: workplace,
                                           template: template, startedOn: day)
            },
            answer: { company, draft in try await service.recordAnswer(identity, company: company, draft: draft) },
            submit: { company, run in try await service.submitRun(identity, company: company, run: run) },
            cancel: { company, run in try await service.cancelRun(identity, company: company, run: run) },
            draftTemplate: { company, title in
                try await service.draftTemplate(identity, company: company, title: title)
            },
            setItem: { company, code, version, item, prompt, allowsNA, position in
                try await service.setItem(identity, company: company, template: code, version: version,
                                          itemCode: item, prompt: prompt,
                                          allowsNotApplicable: allowsNA, position: position)
            },
            removeItem: { company, code, version, item in
                try await service.removeItem(identity, company: company, template: code,
                                             version: version, itemCode: item)
            },
            publishTemplate: { company, code, version, note in
                try await service.publishTemplate(identity, company: company, template: code,
                                                  version: version, note: note)
            })
    }
}
