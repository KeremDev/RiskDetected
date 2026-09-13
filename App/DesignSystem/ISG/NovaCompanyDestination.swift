import SwiftUI

/// Lifecycle-bound feature destination. The composition root injects the existing service;
/// no singleton, Auth SDK or live endpoint is pulled into the design system or QA host.
struct NovaCompanyDestination: View {
    @Binding var host: NovaSessionHost
    let loadCompanies: @MainActor (Bool) async throws -> [NovaOwnedCompany]
    var includeArchived = false
    let onSelect: (UUID) -> Void
    let onBack: () -> Void
    @State private var state = NovaCompanyListState()
    @State private var refresh = UUID()

    private struct LoadKey: Equatable { let epoch: String; let archived: Bool; let refresh: UUID }
    var body: some View {
        let current = state.content(host: host, includeArchived: includeArchived)
        let epoch = host.navigation.epoch
        NovaCompaniesScreen(companies: current.rows.map { .init(id: $0.id.uuidString.lowercased(), name: $0.name, detail: $0.detail) },
            isLoading: current.phase == .loading || current.phase == .idle,
            error: current.phase == .failed ? "Firmalar yüklenemedi. Lütfen tekrar deneyin." : nil,
            isOwnedList: true,
            onSelect: { raw in
                guard let id = UUID(uuidString: raw), let selected = state.select(id, requestID: current.requestID, host: host, includeArchived: includeArchived) else { return }
                onSelect(selected.id)
            }, onBack: { if host.isCurrent(epoch) { onBack() } },
            onRetry: { if host.isCurrent(epoch) { refresh = UUID() } })
        .id(epoch) // The previous account's search text/focus must not survive the host boundary.
        .task(id: LoadKey(epoch: epoch, archived: includeArchived, refresh: refresh)) {
            guard let ticket = state.begin(host: host, includeArchived: includeArchived) else { return }
            do {
                let rows = try await loadCompanies(includeArchived)
                try Task.checkCancellation()
                state.complete(ticket, rows: rows, host: host)
            } catch is CancellationError {
                state.cancel(ticket, host: host)
            } catch {
                if Task.isCancelled { state.cancel(ticket, host: host) }
                else { state.fail(ticket, host: host) }
            }
        }
    }
}
