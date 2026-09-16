import SwiftUI

/// One presentation owns company lookup and the company-specific form.
struct NovaCompanyCreateFlow<Catalogue, Content: View>: View {
    let title: String
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let catalogue: (UUID?) async throws -> Catalogue
    let onSelect: (UUID) -> Void
    var fixedCompany: UUID?
    // `content` also gets the selected company id directly, alongside the
    // catalogue. It used to be Catalogue-only, forcing every caller that
    // needed the company inside its form to stash it via `onSelect` into
    // its own @State and read that back from `content` — but `onSelect`
    // mutates state on the PARENT view while `loaded`/`selected` below are
    // this view's own state, so the two updates could land in different
    // SwiftUI render passes. The visible symptom: opening any of these add
    // flows straight from the menu would flash a "Firma seçimi kayboldu"
    // (or a disabled save button) for a frame before the form caught up.
    // Handing the id straight to `content` from the same state that gates
    // this branch removes the round trip, and with it the race.
    @ViewBuilder let content: (Catalogue, UUID) -> Content
    @State private var options: [NovaAnalysisCompanyOption] = []
    @State private var search = ""
    @State private var selected: NovaAnalysisCompanyOption?
    @State private var loaded: Catalogue?
    @State private var busy = false
    @State private var formBusy = false
    @State private var companyBarHeight: CGFloat = 44
    @State private var failure: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            if let loaded, let selected {
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        Image(systemName: "building.2").font(.system(size: 16, weight: .regular))
                        NovaText(text: selected.name, style: .label).lineLimit(2)
                        Spacer(minLength: 8)
                        if fixedCompany == nil { Button { self.loaded = nil; self.selected = nil } label: {
                            Label("Değiştir", systemImage: "arrow.left.arrow.right")
                                .font(NovaFont.font(.micro)).fixedSize().frame(minHeight: 36)
                        }.buttonStyle(.plain).disabled(formBusy) }
                    }.padding(.horizontal, 14).padding(.vertical, 4)
                    .novaControlBackground(cornerRadius: 14)
                    .padding(.horizontal, 20).padding(.top, 4)
                    .background(GeometryReader { proxy in Color.clear.preference(key: NovaCompanyBarHeightKey.self, value: proxy.size.height) })
                    content(loaded, selected.id).id(selected.id)
                        .transformPreference(NovaPopupHeightKey.self) { $0 += companyBarHeight }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        NovaPopupHeading(text: title, symbol: "building.2", subtitle: "Kaydı eklemek istediğiniz firmayı seçin.")
                        HStack {
                            Image(systemName: "magnifyingglass")
                            TextField("Firma ara", text: $search)
                                .autocorrectionDisabled()
                        }.font(NovaFont.font(.body)).padding(12).novaControlBackground(cornerRadius: 14)
                        if busy { ProgressView("Yükleniyor…").frame(maxWidth: .infinity) }
                        if let failure {
                            Text(failure).font(NovaFont.font(.meta))
                            Button("Yeniden dene") { Task { await loadCompanies() } }
                        }
                        let matches = options.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
                        if matches.isEmpty && !busy && failure == nil {
                            NovaText(text: options.isEmpty ? "Henüz firma yok. Firmalar bölümünden firma ekleyebilirsiniz." : "Aramanıza uygun firma bulunamadı.", style: .body)
                        }
                        ForEach(matches) { company in
                            NovaPopupOption(title: company.name, symbol: "building.2", subtitle: company.detail.isEmpty ? nil : company.detail) {
                                Task { await select(company) }
                            }.disabled(busy)
                        }
                    }.padding(20).novaPopupContentSize()
                }
            }
        }
        .onPreferenceChange(NovaCompanyBarHeightKey.self) { companyBarHeight = $0 }
        .onPreferenceChange(NovaPopupBusyKey.self) { formBusy = $0 }
        .task { await loadCompanies() }
    }
    private func loadCompanies() async {
        busy = true; failure = nil
        defer { busy = false }
        do {
            options = try await companies().filter { fixedCompany == nil || $0.id == fixedCompany }
            if let fixedCompany, let match = options.first(where: { $0.id == fixedCompany }) { await select(match) }
        }
        catch { failure = "Firmalar yüklenemedi. Lütfen tekrar deneyin." }
    }
    private func select(_ company: NovaAnalysisCompanyOption) async {
        busy = true; failure = nil
        defer { busy = false }
        do {
            let result = try await catalogue(company.id)
            guard !Task.isCancelled else { return }
            onSelect(company.id); selected = company; loaded = result
        } catch { failure = "Firma bilgileri yüklenemedi. Firma seçimini yeniden deneyin." }
    }
}

private struct NovaCompanyBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
