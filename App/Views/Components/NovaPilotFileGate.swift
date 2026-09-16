import SwiftUI

/// The Diğer Dosyalar surface. The page answers the whole account in one read
/// and narrows to one company only when the expert asks it to.
struct NovaPilotFileGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    /// Opened from a company page: the archive starts on that company, and on
    /// that heading's own categories when one was named.
    var initialCompany: UUID?
    var initialCategories: [String]?
    var headingOverride: String?
    var startInAddMode = false
    let onBack: () -> Void

    private var service: NovaFileLibraryService { .live() }

    var body: some View {
        NovaFileLibraryScreen(client: client, onBack: onBack, canWrite: canWrite,
            initialCompany: initialCompany, initialCategories: initialCategories,
            headingOverride: headingOverride, startInAddMode: startInAddMode)
    }

    /// Every call carries the signed-in session, which the service re-checks on
    /// both sides. There is no workspace scope to borrow: the archive spans
    /// every company the account owns and each row names its own.
    private var client: NovaFileLibraryClient {
        .init(
            catalogue: { try await service.catalogue(identity) },
            library: { request in try await service.library(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            file: { company, draft, data in
                try await service.file(identity, company: company, draft: draft, data: data)
            },
            rename: { entry, title, category, note in
                try await service.rename(identity, entry: entry, title: title, category: category, note: note)
            },
            archive: { entry in try await service.archive(identity, entry: entry) },
            cancel: { entry in try await service.cancel(identity, entry: entry) },
            recheck: { entry in try await service.recheck(identity, entry: entry) },
            contents: { entry in try await service.contents(identity, entry: entry) },
            download: { bucket, path in try await service.download(identity, bucket: bucket, path: path) })
    }
}


extension NovaFileLibraryClient {
    @MainActor static func pilot(_ identity: NovaSessionIdentity) -> NovaFileLibraryClient {
        let service = NovaFileLibraryService.live()
        return .init(
            catalogue: { try await service.catalogue(identity) },
            library: { request in try await service.library(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            file: { company, draft, data in
                try await service.file(identity, company: company, draft: draft, data: data)
            },
            rename: { entry, title, category, note in
                try await service.rename(identity, entry: entry, title: title, category: category, note: note)
            },
            archive: { entry in try await service.archive(identity, entry: entry) },
            cancel: { entry in try await service.cancel(identity, entry: entry) },
            recheck: { entry in try await service.recheck(identity, entry: entry) },
            contents: { entry in try await service.contents(identity, entry: entry) },
            download: { bucket, path in try await service.download(identity, bucket: bucket, path: path) })
    }
}
