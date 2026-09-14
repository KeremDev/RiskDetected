import SwiftUI

/// The İSG-KATİP Sözleşmeleri surface: the expert's own record of the service
/// contract. The application never acts on the official system.
struct NovaPilotKatipGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    let onBack: () -> Void

    private var service: NovaKatipService { .live() }

    var body: some View {
        NovaKatipScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, headingOverride: headingOverride)
    }

    private var client: NovaKatipClient {
        .init(
            catalogue: { company in try await service.catalogue(identity, company: company) },
            board: { request in try await service.board(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            detail: { contract in try await service.detail(identity, contract: contract) },
            record: { company, draft in try await service.record(identity, company: company, draft: draft) },
            end: { company, draft in try await service.end(identity, company: company, draft: draft) },
            archive: { company, contract in
                try await service.archive(identity, company: company, contract: contract) },
            openDocument: { contractID in
                let contract = try await service.detail(identity, contract: contractID)
                guard contract.contractStored, let fileID = contract.fileEntryID else { throw NovaKatipFailure.validation }
                let library = NovaFileLibraryService.live()
                let file = try await library.detail(identity, entry: fileID)
                guard file.companyID == contract.companyID else { throw NovaKatipFailure.denied }
                let data = try await library.contents(identity, entry: file)
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("katip-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let ext = file.fileExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                let url = folder.appendingPathComponent("Sozlesme").appendingPathExtension(ext)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                return url
            },
            documents: { company, offset in
                var query = NovaFileQuery(); query.company = company; query.state = "promoted"; query.limit = 20; query.offset = offset
                return try await NovaFileLibraryService.live().library(identity, query: query).rows
            },
            linkDocument: { contract, file in try await service.linkDocument(identity, contract: contract, file: file) },
            hasPending: { try service.hasPending(identity) },
            resume: { try await service.resume(identity) })
    }
}
