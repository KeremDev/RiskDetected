import SwiftUI

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
                        }.font(.custom("PlusJakartaSans-Medium", size: 14))
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
        }.scrollDismissesKeyboard(.interactively).background(NovaKeyboardDismissArea())
            .alert(RDLocalization.string("localizable.nova.visual.16", table: .localizable, fallback: "Tasarım önizlemesi"), isPresented: $notice) {
                Button(RDLocalization.string("localizable.nova.visual.17", table: .localizable, fallback: "Tamam"), role: .cancel) { }
            } message: { Text(RDLocalization.string("localizable.nova.visual.18", table: .localizable, fallback: "Sunucu bağlantısı henüz yok. Firma bilgileriniz değiştirilmedi.")) }
    }
    private func field(_ title: String, _ symbol: String, _ value: Binding<String>) -> some View {
        HStack(spacing: 10) { Image(systemName: symbol); TextField(title, text: value) }
            .font(.custom("PlusJakartaSans-Medium", size: 14)).frame(minHeight: 32)
    }
}

struct NovaCompanyVisualDelete: View {
    let name: String
    @State private var notice = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(RDLocalization.string("localizable.nova.visual.19", table: .localizable, fallback: "Firmayı Sil"), systemImage: "trash").font(.headline).foregroundStyle(.red)
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
