import SwiftUI

/// The company-detail editor writes through the existing CompanyService and
/// uploads the selected logo to the company's own storage path.
struct NovaCompanyLiveEditor: View {
    let company: Company?
    let fallbackID: UUID
    let fallbackName: String
    let fallbackHazard: String
    let onSaved: (Company) async -> Void
    @State private var draft: CompanyDraft
    @State private var saving = false
    @State private var error: String?
    @Environment(\.novaCelebrate) private var celebrate

    init(company: Company?, fallbackID: UUID, fallbackName: String, fallbackHazard: String,
         onSaved: @escaping (Company) async -> Void) {
        self.company = company; self.fallbackID = fallbackID; self.fallbackName = fallbackName
        self.fallbackHazard = fallbackHazard; self.onSaved = onSaved
        var value = CompanyDraft()
        value.id = company?.id ?? fallbackID
        value.name = company?.name ?? fallbackName
        value.hazardClass = company?.hazardClass ?? CompanyHazardClass(rawValue: fallbackHazard) ?? .medium
        value.logoPath = company?.logoPath
        value.address = company?.address ?? ""
        value.contactPerson = company?.contactPerson ?? ""
        value.department = company?.department ?? ""
        value.defaultResponsible = company?.defaultResponsible ?? ""
        value.defaultDueDaysText = company?.defaultDueDays.map(String.init) ?? ""
        _draft = State(initialValue: value)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: RDLocalization.string("localizable.nova.company.editor.title", table: .localizable,
                    fallback: "Firma Bilgilerini Güncelle"), style: .sectionTitle)
                NovaCard(padding: 14) {
                    VStack(spacing: 14) {
                        field(RDLocalization.string("localizable.company.picker.sheet.firma.adi.32866b14", table: .localizable,
                            fallback: "Firma adı"), text: $draft.name, symbol: "building.2")
                        Picker(RDLocalization.string("localizable.nova.visual.6", table: .localizable,
                            fallback: "Tehlike sınıfı"), selection: $draft.hazardClass) {
                            ForEach(CompanyHazardClass.allCases) { value in Text(value.title).tag(value) }
                        }.font(NovaFont.font(.body))
                        field("Adres", text: $draft.address, symbol: "mappin")
                        field(RDLocalization.string("localizable.company.picker.sheet.ilgili.kisi.c54dd4c6", table: .localizable,
                            fallback: "İlgili kişi"), text: $draft.contactPerson, symbol: "person")
                        field("Departman / ekip", text: $draft.department, symbol: "person.3")
                    }
                }
                if let error { NovaHelpHint(text: error) }
                NovaButton(label: saving ? "Kaydediliyor…" : "Kaydet", symbol: saving ? "hourglass" : "checkmark",
                    isEnabled: !saving && draft.isValid) { save() }
            }.padding(18).novaPopupContentSize()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20)
            TextField(title, text: text).font(NovaFont.font(.body))
        }.frame(minHeight: 42)
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                let saved = try await CompanyService.shared.saveCompany(draft)
                celebrate(NovaSuccessMessage.companyUpdated)
                await onSaved(saved)
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

/// Explicitly visual-only until scoped pilot mutation endpoints are connected.
struct NovaCompanyVisualEditor: View {
    @State var name: String
    @State var sector: String
    @State var email: String
    @State var hazard: String
    @State private var employees = ""
    @State private var showContact = false
    @State private var contact = ""
    @State private var notice = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NovaText(text: RDLocalization.string("localizable.nova.visual.4", table: .localizable, fallback: "Firmayı Güncelle"), style: .sectionTitle)
                NovaCard(padding: 14) {
                    VStack(spacing: 16) {
                        field(RDLocalization.string("localizable.nova.visual.5", table: .localizable, fallback: "Firma adı *"), "building.2", $name)
                        Picker(RDLocalization.string("localizable.nova.visual.6", table: .localizable, fallback: "Tehlike sınıfı"), selection: $hazard) {
                            Text(RDLocalization.string("localizable.nova.visual.7", table: .localizable, fallback: "Az Tehlikeli")).tag("low")
                            Text(RDLocalization.string("localizable.nova.visual.8", table: .localizable, fallback: "Tehlikeli")).tag("medium")
                            Text(RDLocalization.string("localizable.nova.visual.9", table: .localizable, fallback: "Çok Tehlikeli")).tag("high")
                        }.font(NovaFont.font(.body))
                        field(RDLocalization.string("localizable.nova.visual.10", table: .localizable, fallback: "Sektör *"), "square.grid.2x2", $sector)
                        field(RDLocalization.string("localizable.nova.visual.11", table: .localizable, fallback: "Firma e-posta"), "envelope", $email).keyboardType(.emailAddress)
                        field(RDLocalization.string("localizable.nova.visual.12", table: .localizable, fallback: "Çalışan sayısı"), "person.2", $employees).keyboardType(.numberPad)
                        Toggle(RDLocalization.string("localizable.nova.visual.13", table: .localizable, fallback: "Sorumlu personel"), isOn: $showContact)
                        if showContact { field(RDLocalization.string("localizable.nova.visual.14", table: .localizable, fallback: "Ad soyad"), "person", $contact) }
                    }
                }
                NovaText(text: RDLocalization.string("localizable.nova.visual.15", table: .localizable, fallback: "Tasarım önizlemesi · Değişiklikler henüz kaydedilmez."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.visual.2", table: .localizable, fallback: "Güncelle"), symbol: "checkmark") { notice = true }
            }.padding(18).novaPopupContentSize()
        }.scrollDismissesKeyboard(.interactively)
            .alert(RDLocalization.string("localizable.nova.visual.16", table: .localizable, fallback: "Tasarım önizlemesi"), isPresented: $notice) {
                Button(RDLocalization.string("localizable.nova.visual.17", table: .localizable, fallback: "Tamam"), role: .cancel) { }
            } message: { Text(RDLocalization.string("localizable.nova.visual.18", table: .localizable, fallback: "Sunucu bağlantısı henüz yok. Firma bilgileriniz değiştirilmedi.")) }
    }
    private func field(_ title: String, _ symbol: String, _ value: Binding<String>) -> some View {
        HStack(spacing: 10) { Image(systemName: symbol); TextField(title, text: value) }
            .font(NovaFont.font(.body)).frame(minHeight: 32)
    }
}

struct NovaCompanyVisualDelete: View {
    let name: String
    @State private var notice = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(RDLocalization.string("localizable.nova.visual.19", table: .localizable, fallback: "Firmayı Sil"), systemImage: "trash").font(NovaFont.font(.cardTitle)).foregroundStyle(.red)
                NovaText(text: name, style: .cardTitle)
                NovaText(text: RDLocalization.string("localizable.nova.visual.20", table: .localizable, fallback: "Bu firmayı silmek istediğinizden emin misiniz?"))
                NovaText(text: RDLocalization.string("localizable.nova.visual.21", table: .localizable, fallback: "Tasarım önizlemesi · Bu ekranda hiçbir kayıt silinmez."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.visual.22", table: .localizable, fallback: "Firmayı sil"), symbol: "trash", variant: .danger) { notice = true }
            }.padding(18).novaPopupContentSize()
        }.alert(RDLocalization.string("localizable.nova.visual.16", table: .localizable, fallback: "Tasarım önizlemesi"), isPresented: $notice) {
            Button(RDLocalization.string("localizable.nova.visual.17", table: .localizable, fallback: "Tamam"), role: .cancel) { }
        } message: { Text(RDLocalization.string("localizable.nova.visual.23", table: .localizable, fallback: "Silme servisi henüz bağlı değil. Hiçbir kayıt silinmedi.")) }
    }
}
