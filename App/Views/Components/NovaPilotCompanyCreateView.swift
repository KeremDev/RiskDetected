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
                        NovaPageHeading(title: "Yeni Firma", subtitle: "Zorunlu alanlar * ile işaretlidir", isBackEnabled: !submitting) { dismiss() }
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                field("Firma adı *", symbol: "building.2", text: $name, id: "name")
                                Divider()
                                HStack(alignment: .center, spacing: 10) {
                                    HStack(spacing: 7) {
                                        NovaIcon(symbol: "exclamationmark.triangle", size: 17).foregroundStyle(NovaColorToken.statusWarningInk.color(in: scheme))
                                        Picker("Tehlike sınıfı *", selection: $hazard) {
                                            ForEach(CompanyHazardClass.allCases) { item in Text(item.title).tag(item) }
                                        }.font(.custom("PlusJakartaSans-Medium", size: 13)).tint(NovaColorToken.text.color(in: scheme))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Divider().frame(height: 30)
                                    field("Sektör *", symbol: "square.grid.2x2", text: $sector, id: "sector")
                                        .frame(maxWidth: .infinity)
                                }.frame(minHeight: 40)
                            }
                        }
                        .disabled(!loaded || submitting || pending != nil || storageFailed)
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 14) {
                                NovaText(text: "Ek bilgiler · isteğe bağlı", style: .label)
                                field("Firma e-posta", symbol: "envelope", text: $email, id: "email", keyboard: .emailAddress)
                                Divider()
                                field("Çalışan sayısı", symbol: "person.2", text: $employeeCount, id: "employeeCount", keyboard: .numberPad)
                                Divider()
                                field("Sicil No", symbol: "number", text: $registryNumber, id: "registryNumber")
                                Divider()
                                Toggle(isOn: $addResponsible) {
                                    Label("Sorumlu personel ekle", systemImage: "person.badge.plus").font(.subheadline)
                                }.tint(NovaColorToken.accent.color(in: scheme))
                                if addResponsible {
                                    field("Ad soyad", symbol: "person", text: $responsibleName, id: "responsible")
                                    NovaText(text: "Bu kişi firmanın personel listesine de eklenir.", style: .metaQuiet)
                                }
                            }
                        }.disabled(!loaded || submitting || pending != nil || storageFailed)
                        Label("Yalnızca pilot kapsamına eklenir. Mevcut firmalarınız değişmez; firma limitiniz geçerlidir.", systemImage: "checkmark.shield")
                            .font(.footnote).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                        if pending != nil {
                            NovaText(text: "Bekleyen işlemi aynı bilgilerle tekrar kontrol edin. İkinci bir firma oluşturulmaz.", style: .metaQuiet)
                        }
                        if let error { NovaText(text: error, color: NovaColorToken.statusDangerInk.color(in: scheme)).accessibilityIdentifier("nova.pilot.company.error") }
                    }
                    .padding(20)
                    .novaPopupContentSize(extra: 76)
                    .background { Color.clear.contentShape(Rectangle()).onTapGesture { focusedField = nil } }
                }.scrollDismissesKeyboard(.interactively)
                    .background(NovaKeyboardDismissArea())
                    .safeAreaInset(edge: .bottom) {
                        NovaButton(label: pending == nil ? "Firmayı kaydet" : "Aynı kaydı tekrar dene", symbol: "checkmark",
                            isEnabled: loaded && !storageFailed, isLoading: submitting) {
                                focusedField = nil
                                guard valid else {
                                    error = "Firma adı ve sektör zorunludur. E-posta, çalışan sayısı ve sorumlu personel bilgilerini kontrol edin."
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
                storageFailed = true; self.error = "Bekleyen kayıt güvenle okunamadı. Kaydı çoğaltmamak için işlem durduruldu."
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
                celebrate("Firmanız başarıyla eklendi!")
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
                TextField(title, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
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
            case "company_limit_exceeded": return "Firma limitinize ulaştınız. Mevcut firmalarınız da bu limite dahildir."
            case "PAID_PLAN_REQUIRED": return "Firma oluşturmak için aktif Plus veya Pro aboneliği gerekiyor."
            case "FEATURE_UNAVAILABLE", "ACCESS_DENIED": return "Pilot yazma erişimi açık değil veya süresi dolmuş. Erişim açıldıktan sonra aynı kaydı tekrar deneyebilirsiniz."
            case "IDEMPOTENCY_CONFLICT": return "Bekleyen işlemin içeriği uyuşmuyor. Yeni kayıt açılmadı; destek kontrolü gerekiyor."
            default: break
            }
        }
        return "İşlemin sonucu doğrulanamadı. Bağlantınızı kontrol edip aynı kaydı tekrar deneyin."
    }
}
