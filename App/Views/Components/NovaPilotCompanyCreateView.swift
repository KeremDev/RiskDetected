import SwiftUI
import Supabase

struct NovaPilotCompanyCreateView: View {
    let identity: NovaSessionIdentity
    let service: NovaPilotCompanyService
    let onCreated: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.novaCelebrate) private var celebrate
    @State private var name = ""
    @State private var hazard: CompanyHazardClass = .medium
    @State private var sector = ""
    @State private var email = ""
    @State private var employeeCount = ""
    @State private var registryNumber = ""
    @State private var addResponsible = false
    @State private var responsibleName = ""
    @Environment(\.colorScheme) private var scheme
    @State private var pending: NovaPilotCompanyIntent?
    @State private var loaded = false
    @State private var storageFailed = false
    @State private var submitting = false
    @State private var error: String?
    @FocusState private var focusedField: String?

    private var valid: Bool {
        if pending != nil { return true }
        return (!addResponsible || !responsibleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (try? makeIntent()) != nil
    }
    private func makeIntent() throws -> NovaPilotCompanyIntent {
        try .makeProfile(ownerID: identity.userID, name: name, hazard: hazard.rawValue, sector: sector,
            email: email, employeeCount: employeeCount, responsibleName: addResponsible ? responsibleName : "")
    }
    var body: some View {
        NavigationStack {
            NovaPageSurface {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        NovaPageHeading(title: RDLocalization.string("localizable.nova.pilot.company.create.view.yeni.firma.458e4f36", table: .localizable, fallback: "Yeni Firma"), subtitle: RDLocalization.string("localizable.nova.pilot.company.create.view.zorunlu.alanlar.ile.isaretlidir.f93191fc", table: .localizable, fallback: "Zorunlu alanlar * ile işaretlidir"), isBackEnabled: !submitting) { dismiss() }
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.firma.adi.15090427", table: .localizable, fallback: "Firma adı *"), symbol: "building.2", text: $name, id: "name")
                                Divider()
                                HStack(alignment: .center, spacing: 10) {
                                    HStack(spacing: 7) {
                                        NovaIcon(symbol: "exclamationmark.triangle", size: 17).foregroundStyle(NovaColorToken.statusWarningInk.color(in: scheme))
                                        Picker(RDLocalization.string("localizable.nova.pilot.company.create.view.tehlike.sinifi.837c3a63", table: .localizable, fallback: "Tehlike sınıfı *"), selection: $hazard) {
                                            ForEach(CompanyHazardClass.allCases) { item in Text(item.title).tag(item) }
                                        }.font(NovaFont.font(.body)).tint(NovaColorToken.text.color(in: scheme))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Divider().frame(height: 30)
                                    field(RDLocalization.string("localizable.nova.pilot.company.create.view.sektor.a0de4868", table: .localizable, fallback: "Sektör *"), symbol: "square.grid.2x2", text: $sector, id: "sector")
                                        .frame(maxWidth: .infinity)
                                }.frame(minHeight: 40)
                            }
                        }
                        .disabled(!loaded || submitting || pending != nil || storageFailed)
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 14) {
                                NovaText(text: RDLocalization.string("localizable.nova.pilot.company.create.view.ek.bilgiler.istege.bagli.a207edd5", table: .localizable, fallback: "Ek bilgiler · isteğe bağlı"), style: .label)
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.firma.e.posta.b818798f", table: .localizable, fallback: "Firma e-posta"), symbol: "envelope", text: $email, id: "email", keyboard: .emailAddress)
                                Divider()
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.calisan.sayisi.4465d142", table: .localizable, fallback: "Çalışan sayısı"), symbol: "person.2", text: $employeeCount, id: "employeeCount", keyboard: .numberPad)
                                Divider()
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.sicil.no.dc1d6d14", table: .localizable, fallback: "Sicil No"), symbol: "number", text: $registryNumber, id: "registryNumber")
                                Divider()
                                Toggle(isOn: $addResponsible) {
                                    Label(RDLocalization.string("localizable.nova.pilot.company.create.view.sorumlu.personel.ekle.779d3a3d", table: .localizable, fallback: "Sorumlu personel ekle"), systemImage: "person.badge.plus").font(NovaFont.font(.body))
                                }.tint(NovaColorToken.accent.color(in: scheme))
                                if addResponsible {
                                    field(RDLocalization.string("localizable.nova.pilot.company.create.view.ad.soyad.54b1adca", table: .localizable, fallback: "Ad soyad"), symbol: "person", text: $responsibleName, id: "responsible")
                                    NovaText(text: RDLocalization.string("localizable.nova.pilot.company.create.view.bu.kisi.firmanin.personel.listesine.de.eklenir.196763c7", table: .localizable, fallback: "Bu kişi firmanın personel listesine de eklenir."), style: .metaQuiet)
                                }
                            }
                        }.disabled(!loaded || submitting || pending != nil || storageFailed)
                        Label(RDLocalization.string("localizable.nova.pilot.company.create.view.yalnizca.pilot.kapsamina.eklenir.mevcut.firmalar.b99c355c", table: .localizable, fallback: "Yalnızca pilot kapsamına eklenir. Mevcut firmalarınız değişmez; firma limitiniz geçerlidir."), systemImage: "checkmark.shield")
                            .font(NovaFont.font(.meta)).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                        if pending != nil {
                            NovaText(text: RDLocalization.string("localizable.nova.pilot.company.create.view.bekleyen.islemi.ayni.bilgilerle.tekrar.kontrol.e.1b29313f", table: .localizable, fallback: "Bekleyen işlemi aynı bilgilerle tekrar kontrol edin. İkinci bir firma oluşturulmaz."), style: .metaQuiet)
                        }
                        if let error { NovaText(text: error, color: NovaColorToken.statusDangerInk.color(in: scheme)).accessibilityIdentifier("nova.pilot.company.error") }
                    }
                    .padding(20)
                    .novaPopupContentSize(extra: 76)
                    .background { Color.clear.contentShape(Rectangle()).onTapGesture { focusedField = nil } }
                }.scrollDismissesKeyboard(.interactively)
                    .background(NovaKeyboardDismissArea())
                    .safeAreaInset(edge: .bottom) {
                        NovaButton(label: pending == nil ? RDLocalization.string("localizable.nova.pilot.company.create.view.firmayi.kaydet.f24d4369", table: .localizable, fallback: "Firmayı kaydet") : RDLocalization.string("localizable.nova.pilot.company.create.view.ayni.kaydi.tekrar.dene.26e3002b", table: .localizable, fallback: "Aynı kaydı tekrar dene"), symbol: "checkmark",
                            isEnabled: loaded && !storageFailed, isLoading: submitting) {
                                focusedField = nil
                                guard valid else {
                                    error = RDLocalization.string("localizable.nova.pilot.company.create.view.firma.adi.ve.sektor.zorunludur.e.posta.calisan.s.0900e170", table: .localizable, fallback: "Firma adı ve sektör zorunludur. E-posta, çalışan sayısı ve sorumlu personel bilgilerini kontrol edin.")
                                    return
                                }
                                submitting = true
                            }
                            .accessibilityIdentifier("nova.pilot.company.submit")
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(NovaColorToken.canvas.color(in: scheme))
                    }
            }
            .interactiveDismissDisabled(submitting)
        }
        .task {
            do {
                pending = try service.pending(identity: identity)
                if let pending {
                    name = pending.name; hazard = CompanyHazardClass(rawValue: pending.hazard) ?? .medium
                    sector = pending.sector ?? ""; email = pending.email ?? ""
                    employeeCount = pending.employeeCount.map(String.init) ?? ""
                    responsibleName = pending.responsibleName ?? ""; addResponsible = pending.responsibleName != nil
                }
                loaded = true
            } catch {
                storageFailed = true; self.error = RDLocalization.string("localizable.nova.pilot.company.create.view.bekleyen.kayit.guvenle.okunamadi.kaydi.cogaltmam.534e3ba3", table: .localizable, fallback: "Bekleyen kayıt güvenle okunamadı. Kaydı çoğaltmamak için işlem durduruldu.")
            }
        }
        .task(id: submitting) {
            guard submitting else { return }
            defer { submitting = false }
            error = nil
            do {
                let intent = try pending ?? makeIntent()
                pending = intent
                let companyID = try await service.create(intent, identity: identity)
                try Task.checkCancellation()
                celebrate(RDLocalization.string("localizable.nova.pilot.company.create.view.firmaniz.basariyla.eklendi.72430314", table: .localizable, fallback: "Firmanız başarıyla eklendi!"))
                onCreated(companyID); dismiss()
            } catch is CancellationError {
                return
            } catch {
                self.error = Self.message(error)
            }
        }
    }

    private func field(_ title: String, symbol: String, text: Binding<String>, id: String, keyboard: UIKeyboardType = .default) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NovaIcon(symbol: symbol, size: 18).foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(width: 22)
                TextField(title, text: text).font(NovaFont.font(.body))
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .keyboardType(keyboard).autocorrectionDisabled()
                    .focused($focusedField, equals: id)
                    .submitLabel(.done).onSubmit { focusedField = nil }
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("nova.pilot.company.\(id)")
        }.frame(minHeight: 40)
    }

    private static func message(_ error: Error) -> String {
        if let error = error as? PostgrestError {
            switch error.message {
            case "company_limit_exceeded": return RDLocalization.string("localizable.nova.pilot.company.create.view.firma.limitinize.ulastiniz.mevcut.firmalariniz.d.2ea1357c", table: .localizable, fallback: "Firma limitinize ulaştınız. Mevcut firmalarınız da bu limite dahildir.")
            case "PAID_PLAN_REQUIRED": return RDLocalization.string("localizable.nova.pilot.company.create.view.firma.olusturmak.icin.aktif.plus.veya.pro.abonel.1f6b8652", table: .localizable, fallback: "Firma oluşturmak için aktif Plus veya Pro aboneliği gerekiyor.")
            case "FEATURE_UNAVAILABLE", "ACCESS_DENIED": return RDLocalization.string("localizable.nova.pilot.company.create.view.pilot.yazma.erisimi.acik.degil.veya.suresi.dolmu.05b49924", table: .localizable, fallback: "Pilot yazma erişimi açık değil veya süresi dolmuş. Erişim açıldıktan sonra aynı kaydı tekrar deneyebilirsiniz.")
            case "IDEMPOTENCY_CONFLICT": return RDLocalization.string("localizable.nova.pilot.company.create.view.bekleyen.islemin.icerigi.uyusmuyor.yeni.kayit.ac.1a4f9f92", table: .localizable, fallback: "Bekleyen işlemin içeriği uyuşmuyor. Yeni kayıt açılmadı; destek kontrolü gerekiyor.")
            default: break
            }
        }
        return RDLocalization.string("localizable.nova.pilot.company.create.view.islemin.sonucu.dogrulanamadi.baglantinizi.kontro.b20e85af", table: .localizable, fallback: "İşlemin sonucu doğrulanamadı. Bağlantınızı kontrol edip aynı kaydı tekrar deneyin.")
    }
}
