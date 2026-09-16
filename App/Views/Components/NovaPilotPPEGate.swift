import SwiftUI

/// KKD is a person handover and downloadable form, without stock or returns.
struct NovaPilotPPEGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    /// Opened from the company page's own empty-state "Ekle" action.
    var startInAddMode = false
    let onBack: () -> Void
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var company: UUID?
    @State private var employee: UUID?
    @State private var rows: [NovaPPEHandover] = []
    @State private var item = ""
    @State private var date = Date()
    @State private var creating = false
    @State private var busy = false
    @State private var loading = false
    @State private var hasMore = false
    @State private var failure: String?
    @State private var pdf: URL?
    private var service: NovaPPEService { .live() }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button(action: onBack) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        NovaText(text: headingOverride ?? "KKD Zimmetleri", style: .cardTitle)
                        Spacer()
                        if canWrite { Button { creating = true } label: { Label("Zimmet", systemImage: "plus") } }
                    }
                    Picker("Firma", selection: $company) {
                        if initialCompany == nil { Text("Tüm firmalar").tag(UUID?.none) }
                        ForEach(companies.filter { initialCompany == nil || $0.id == initialCompany }) { Text($0.name).tag(Optional($0.id)) }
                    }.tint(.primary)
                    if loading { ProgressView("Zimmetler yükleniyor…").frame(maxWidth: .infinity) }
                    if let failure { Text(failure).font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk) }
                    if rows.isEmpty && !loading {
                        NovaCard(padding: 22) {
                            NovaText(text: "Henüz zimmet kaydı yok. Firma personeline KKD zimmeti oluşturabilirsiniz.", style: .body)
                        }
                    }
                    ForEach(rows) { row in
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 9) {
                                NovaText(text: row.employeeName ?? "Personel", style: .cardTitle)
                                NovaText(text: row.item, style: .body)
                                NovaText(text: "\(row.companyName ?? "") · \(row.handedOn)", style: .meta)
                                Button { Task { await download(row.id) } } label: {
                                    Label("Zimmet formunu indir", systemImage: "arrow.down.doc")
                                }.disabled(busy)
                            }
                        }
                    }
                    if hasMore { Button("Daha fazla göster") { Task { await load(more: true) } }.disabled(loading) }
                }.padding(16)
            }
        }
        .font(NovaFont.font(.body))
        .foregroundStyle(NovaColorToken.text.color(in: scheme))
        .task { company = initialCompany; await load() }
        .onChange(of: company) { _ in Task { await load() } }
        .onAppear { if startInAddMode && canWrite { creating = true } }
        .sheet(isPresented: $creating) {
            NovaCompanyCreateFlow(title: "KKD zimmeti", companies: {
                try await NovaAnalysisWorkspace.companyOptions(identity: identity)
            }, catalogue: { selected in
                try await service.catalogue(identity, company: selected)
            }, onSelect: { _ in employee = nil }, fixedCompany: initialCompany) { catalogue, company in
                editor(catalogue, company)
            }
        }
        .sheet(item: $pdf) { NovaFileShareSheet(url: $0) }
    }

    private func editor(_ catalogue: NovaPPECatalogue, _ company: UUID) -> some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                NovaText(text: "KKD zimmeti", style: .screenTitle)
                Picker("Personel", selection: $employee) {
                    Text("Personel seçin").tag(UUID?.none)
                    ForEach(catalogue.employees) { Text($0.fullName).tag(Optional($0.id)) }
                }.disabled(busy)
                Section("Zimmet verilen KKD") {
                    TextField("Örn. baret, koruyucu gözlük, iş ayakkabısı", text: $item, axis: .vertical)
                        .lineLimit(3...6)
                    Text("KKD adlarını yazın. En fazla 200 karakter.").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                }
                DatePicker("Teslim tarihi", selection: $date, in: ...Date(), displayedComponents: .date)
                if let failure { Text(failure).font(NovaFont.font(.meta)) }
                Button(busy ? "Kaydediliyor…" : "Zimmeti kaydet") { Task { await save(company: company) } }
                    .disabled(busy || employee == nil || item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.count > 200)
            }
                .padding(20).novaPopupContentSize()
            }
            .font(NovaFont.font(.body))
        }
        .preference(key: NovaPopupBusyKey.self, value: busy)
        .interactiveDismissDisabled(busy)
    }

    private func load(more: Bool = false) async {
        let selected = company
        loading = true; failure = nil
        defer { loading = false }
        do {
            if companies.isEmpty { companies = try await NovaAnalysisWorkspace.companyOptions(identity: identity) }
            var query = NovaPPEQuery(); query.company = selected; query.offset = more ? rows.count : 0
            let result = try await service.board(identity, query: query)
            guard selected == company else { return }
            rows = more ? rows + result.rows : result.rows; hasMore = result.hasMore
        } catch { failure = "Zimmetler yüklenemedi. Lütfen tekrar deneyin." }
    }
    private func save(company: UUID) async {
        guard let employee else { return }
        busy = true; failure = nil
        defer { busy = false }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Europe/Istanbul"); formatter.dateFormat = "yyyy-MM-dd"
        do {
            try await service.createForm(identity, company: company, employee: employee,
                item: item.trimmingCharacters(in: .whitespacesAndNewlines), date: formatter.string(from: date))
            creating = false; item = ""; await load()
        } catch { failure = "Zimmet kaydedilemedi. Bilgileri kontrol edip tekrar deneyin." }
    }
    private func download(_ id: UUID) async {
        busy = true; failure = nil
        defer { busy = false }
        do {
            let snapshot = try await service.form(identity, id: id)
            pdf = try NovaPPEFormPDF.write(snapshot, owner: identity.userID)
        } catch { failure = "Zimmet formu hazırlanamadı. Lütfen tekrar deneyin." }
    }
}
