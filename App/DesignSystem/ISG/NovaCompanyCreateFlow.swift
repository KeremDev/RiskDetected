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
    @State private var failure: String?

    var body: some View {
        NovaPopup {
            if let loaded, let selected {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "building.2")
                        NovaText(text: selected.name, style: .label)
                        Spacer(minLength: 8)
                        if fixedCompany == nil { Button("Değiştir") { self.loaded = nil; self.selected = nil }.disabled(formBusy) }
                    }.padding(.horizontal, 20).padding(.vertical, 12)
                    content(loaded, selected.id).id(selected.id)
                        .transformPreference(NovaPopupHeightKey.self) { $0 += 65 }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        NovaText(text: title, style: .screenTitle)
                        NovaText(text: "Devam etmek için firma seçin", style: .body)
                        HStack {
                            Image(systemName: "magnifyingglass")
                            TextField("Firma ara", text: $search)
                                .autocorrectionDisabled()
                        }.padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
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
                            Button { Task { await select(company) } } label: {
                                HStack {
                                    NovaText(text: company.name, style: .body)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).disabled(busy)
                        }
                    }.padding(20).novaPopupContentSize()
                }
            }
        }
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
