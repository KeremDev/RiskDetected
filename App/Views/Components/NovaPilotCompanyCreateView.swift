import SwiftUI
import Supabase

/// Company creation is a short, resumable wizard. Each step keeps the main
/// task small while the final review makes the write explicit.
struct NovaPilotCompanyCreateView: View {
    let identity: NovaSessionIdentity
    let service: NovaPilotCompanyService
    let onCreated: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.novaCelebrate) private var celebrate
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedField: String?

    @State private var name = ""
    @State private var address = ""
    @State private var city = ""
    @State private var phone = ""
    @State private var hazard: CompanyHazardClass = .medium
    @State private var sector = ""
    @State private var employeeCount = ""
    @State private var naceCode = ""
    @State private var workplaceRegistryNo = ""
    @State private var workplaces: [CompanyWorkplaceProfile] = []
    @State private var departments: [String] = []
    @State private var addResponsible = false
    @State private var contacts: [CompanyResponsibleContact] = []
    @State private var email = ""
    @State private var pending: NovaPilotCompanyIntent?
    @State private var loaded = false
    @State private var storageFailed = false
    @State private var submitting = false
    @State private var error: String?
    @State private var step = 0
    @State private var saved = false

    private let roles = [RDLocalization.string("localizable.nova.pilot.company.create.view.firma.sahibi.586f27b4", table: .localizable, fallback: "Firma Sahibi"), RDLocalization.string("localizable.nova.pilot.company.create.view.firma.muduru.e25de85f", table: .localizable, fallback: "Firma Müdürü"), RDLocalization.string("localizable.nova.pilot.company.create.view.bolum.sorumlusu.ab7845ff", table: .localizable, fallback: "Bölüm Sorumlusu"), RDLocalization.string("localizable.nova.pilot.company.create.view.is.guvenligi.uzmani.7f2da173", table: .localizable, fallback: "İş Güvenliği Uzmanı"), RDLocalization.string("localizable.nova.pilot.company.create.view.insan.kaynaklari.f5b2ad81", table: .localizable, fallback: "İnsan Kaynakları"), RDLocalization.string("localizable.nova.pilot.company.create.view.idari.isler.a1b7a67c", table: .localizable, fallback: "İdari İşler"), RDLocalization.string("localizable.nova.pilot.company.create.view.diger.491a7bcb", table: .localizable, fallback: "Diğer")]
    private var totalSteps: Int { 5 }
    private var stepTitles: [String] { [RDLocalization.string("localizable.nova.pilot.company.create.view.firma.bilgileri.b86a63f5", table: .localizable, fallback: "Firma bilgileri"), RDLocalization.string("localizable.nova.pilot.company.create.view.isletme.bilgileri.8535ee6d", table: .localizable, fallback: "İşletme bilgileri"), RDLocalization.string("localizable.nova.pilot.company.create.view.isyeri.ve.departman.37216e23", table: .localizable, fallback: "İşyeri ve departman"), RDLocalization.string("localizable.nova.pilot.company.create.view.sorumlu.iletisim.dc37528c", table: .localizable, fallback: "Sorumlu & iletişim"), RDLocalization.string("localizable.nova.pilot.company.create.view.firma.ozeti.f301afc4", table: .localizable, fallback: "Firma özeti")] }
    private var firstContact: CompanyResponsibleContact? { contacts.first }

    private var workplaceToggle: Binding<Bool> {
        Binding(
            get: { !workplaces.isEmpty },
            set: { enabled in
                if enabled {
                    if workplaces.isEmpty { workplaces = [.init()] }
                } else {
                    workplaces.removeAll()
                }
            }
        )
    }

    private var departmentToggle: Binding<Bool> {
        Binding(
            get: { !departments.isEmpty },
            set: { enabled in
                if enabled {
                    if departments.isEmpty { departments = [""] }
                } else {
                    departments.removeAll()
                }
            }
        )
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return !name.trimmed.isEmpty
        case 1: return !sector.trimmed.isEmpty && Int(employeeCount.trimmed) != nil
        case 2:
            let workplaceOK = workplaces.allSatisfy { !$0.name.trimmed.isEmpty }
            let departmentOK = departments.allSatisfy { !$0.trimmed.isEmpty }
            return workplaceOK && departmentOK
        case 3:
            guard addResponsible, !contacts.isEmpty else { return true }
            return contacts.allSatisfy { !$0.name.trimmed.isEmpty && !$0.phone.trimmed.isEmpty && !$0.role.trimmed.isEmpty }
        default: return true
        }
    }

    private func makeIntent() throws -> NovaPilotCompanyIntent {
        let contact = firstContact
        return try .makeContactProfile(ownerID: identity.userID, name: name, hazard: hazard.rawValue,
            sector: sector, email: email, employeeCount: employeeCount,
            responsibleName: addResponsible ? (contact?.name ?? "") : "",
            responsiblePhone: addResponsible ? (contact?.phone ?? "") : "",
            responsibleEmail: addResponsible ? (contact?.email ?? "") : "")
    }

    var body: some View {
        Group {
            if saved {
                NovaTaskSuccessView(title: RDLocalization.string("localizable.nova.pilot.company.create.view.firma.olusturuldu.18db6902", table: .localizable, fallback: "Firma oluşturuldu"),
                    message: RDLocalization.string("localizable.nova.pilot.company.create.view.firma.bilgileri.kaydedildi.ve.ilgili.modullerde..ef4b6c3c", table: .localizable, fallback: "Firma bilgileri kaydedildi ve ilgili modüllerde kullanılmaya hazır."),
                    doneTitle: RDLocalization.string("localizable.nova.pilot.company.create.view.firmaya.git.3269843a", table: .localizable, fallback: "Firmaya git"), onDone: { dismiss() })
            } else {
                NovaPageSurface(onEdgeBack: goBack) {
                    VStack(spacing: 0) {
                        NovaTaskHeader(title: RDLocalization.string("localizable.nova.pilot.company.create.view.firma.ekle.3dc49f78", table: .localizable, fallback: "Firma ekle"), step: step + 1, total: totalSteps,
                            stepTitle: stepTitles[step], onClose: goBack)
                            .padding(.horizontal, 18).padding(.top, 8)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                stepContent
                                if pending != nil {
                                    NovaText(text: RDLocalization.string("localizable.nova.pilot.company.create.view.bekleyen.islem.bulundu.ayni.kayit.tekrar.gonderi.f54f5523", table: .localizable, fallback: "Bekleyen işlem bulundu. Aynı kayıt tekrar gönderilebilir; yeni bir firma oluşturulmaz."), style: .metaQuiet)
                                }
                                if let error { NovaTaskErrorSummary(message: error) }
                            }
                            .padding(20).padding(.bottom, 12)
                            .background { Color.clear.contentShape(Rectangle()).onTapGesture { focusedField = nil } }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == totalSteps - 1 ? RDLocalization.string("localizable.nova.pilot.company.create.view.firma.ekle.bc679ac7", table: .localizable, fallback: "Firma Ekle") : RDLocalization.string("localizable.nova.pilot.company.create.view.devam.712f2cec", table: .localizable, fallback: "Devam"),
                                primarySymbol: step == totalSteps - 1 ? "checkmark" : "arrow.right",
                                isWorking: submitting, canGoBack: true, onBack: goBack, onPrimary: advance)
                                .accessibilityIdentifier(step == totalSteps - 1 ? "nova.pilot.company.submit" : "nova.pilot.company.next")
                        }
                    }
                }
                .interactiveDismissDisabled(submitting)
            }
        }
        .task { await loadPending() }
        .task(id: submitting) {
            guard submitting else { return }
            defer { submitting = false }
            error = nil
            do {
                let freshIntent = try makeIntent()
                // If a staged request exists and the user changed the wizard,
                // first reconcile that request. This reuses its idempotent
                // company row, then the richer profile update below applies
                // the edited fields without creating a duplicate company.
                let companyID: UUID
                if let staged = pending {
                    companyID = try await service.create(staged, identity: identity)
                } else {
                    companyID = try await service.create(freshIntent, identity: identity)
                }
                pending = nil
                // The pilot RPC creates the secure base row. Persist the richer
                // wizard profile immediately afterwards with the same owner.
                var draft = CompanyDraft()
                draft.id = companyID; draft.name = name.trimmed; draft.hazardClass = hazard
                draft.address = address.trimmed; draft.city = city.trimmed; draft.phone = phone.trimmed
                draft.naceCode = naceCode.trimmed; draft.workplaceRegistryNo = workplaceRegistryNo.trimmed
                draft.departments = departments.map(\.trimmed).filter { !$0.isEmpty }
                draft.department = draft.departments.first ?? ""
                draft.contactPerson = firstContact?.name.trimmed ?? ""
                draft.defaultResponsible = firstContact?.name.trimmed ?? ""
                draft.workplaceProfiles = workplaces
                draft.workplaceProfile = workplaces.first
                draft.responsibleContacts = addResponsible ? contacts : []
                _ = try? await CompanyService.shared.saveCompany(draft)
                try Task.checkCancellation()
                celebrate(NovaSuccessMessage.companyCreated)
                onCreated(companyID); saved = true
            } catch is CancellationError { return }
            catch { self.error = Self.message(error) }
        }
    }

    @MainActor private func loadPending() async {
        do {
            pending = try service.pending(identity: identity)
            if let pending {
                name = pending.name; hazard = CompanyHazardClass(rawValue: pending.hazard) ?? .medium
                sector = pending.sector ?? ""; employeeCount = pending.employeeCount.map(String.init) ?? ""
                email = pending.email ?? ""
                if let person = pending.responsibleName {
                    addResponsible = true
                    contacts = [.init(name: person, phone: pending.responsiblePhone ?? "", email: pending.responsibleEmail ?? "", role: RDLocalization.string("localizable.nova.pilot.company.create.view.diger.7734aa7f", table: .localizable, fallback: "Diğer"))]
                }
            }
            loaded = true
        } catch {
            storageFailed = true
            self.error = RDLocalization.string("localizable.nova.pilot.company.create.view.bekleyen.kayit.guvenle.okunamadi.kaydi.cogaltmam.0f98e12e", table: .localizable, fallback: "Bekleyen kayıt güvenle okunamadı. Kaydı çoğaltmamak için işlem durduruldu.")
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: companyStep
        case 1: businessStep
        case 2: workplaceStep
        case 3: responsibleStep
        default: reviewStep
        }
    }

    private var companyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaHelpHint(text: RDLocalization.string("localizable.nova.pilot.company.create.view.firma.bilgileri.bir.kez.secilir.sonraki.modul.ka.9c299bc6", table: .localizable, fallback: "Firma bilgileri bir kez seçilir; sonraki modül kayıtlarına otomatik taşınır."))
            NovaCard(padding: 16) {
                VStack(spacing: 10) {
                    field(RDLocalization.string("localizable.nova.pilot.company.create.view.firma.adi.5ccc5d6e", table: .localizable, fallback: "Firma adı *"), symbol: "building.2", text: $name, id: "name")
                    Divider(); field(RDLocalization.string("localizable.nova.pilot.company.create.view.adres.734770bb", table: .localizable, fallback: "Adres"), symbol: "mappin.and.ellipse", text: $address, id: "address")
                    Divider(); field(RDLocalization.string("localizable.nova.pilot.company.create.view.sehir.26ac263b", table: .localizable, fallback: "Şehir"), symbol: "map", text: $city, id: "city")
                    Divider(); field(RDLocalization.string("localizable.nova.pilot.company.create.view.firma.telefonu.c09d4db9", table: .localizable, fallback: "Firma telefonu"), symbol: "phone", text: $phone, id: "phone", keyboard: .phonePad)
                }
            }
        }
        .disabled(!loaded || submitting || storageFailed)
    }

    private var businessStep: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                hazardPicker(title: RDLocalization.string("localizable.nova.pilot.company.create.view.tehlike.sinifi.947b4a96", table: .localizable, fallback: "Tehlike sınıfı *"), selection: $hazard)
                Divider(); field(RDLocalization.string("localizable.nova.pilot.company.create.view.sektor.61c5178e", table: .localizable, fallback: "Sektör *"), symbol: "square.grid.2x2", text: $sector, id: "sector")
                Divider(); field(RDLocalization.string("localizable.nova.pilot.company.create.view.calisan.sayisi.6b061e7f", table: .localizable, fallback: "Çalışan sayısı *"), symbol: "person.2", text: $employeeCount, id: "employeeCount", keyboard: .numberPad)
                Divider(); field(RDLocalization.string("localizable.nova.pilot.company.create.view.nace.kodu.ea82912c", table: .localizable, fallback: "NACE kodu"), symbol: "number", text: $naceCode, id: "nace")
                Divider(); field(RDLocalization.string("localizable.nova.pilot.company.create.view.isyeri.sicil.no.e9e2e9ee", table: .localizable, fallback: "İşyeri sicil no"), symbol: "doc.text", text: $workplaceRegistryNo, id: "registry")
            }
        }
        .disabled(!loaded || submitting || storageFailed)
    }

    private var workplaceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(RDLocalization.string("localizable.nova.pilot.company.create.view.ayni.firmaya.ait.farkli.isyeri.var.mi.3455a600", table: .localizable, fallback: "Aynı firmaya ait farklı işyeri var mı?"), isOn: workplaceToggle).tint(NovaColorToken.accent.color(in: scheme))
                    if !workplaces.isEmpty {
                        ForEach(workplaces.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    NovaText(text: RDLocalization.format("localizable.nova.pilot.company.create.view.isyeri.1.8358bf35", table: .localizable, fallback: "İşyeri %1$@", arguments: [String(describing: index + 1)]), style: .label)
                                    Spacer()
                                    if index > 0 {
                                        Button { workplaces.remove(at: index) } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                                                .frame(width: 32, height: 32)
                                        }.buttonStyle(.plain)
                                    }
                                }
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.isyeri.adi.f37b0266", table: .localizable, fallback: "İşyeri adı *"), symbol: "building.2", text: $workplaces[index].name, id: "workplace-\(index)-name")
                                hazardPicker(title: RDLocalization.string("localizable.nova.pilot.company.create.view.isyeri.tehlike.sinifi.5515503a", table: .localizable, fallback: "İşyeri tehlike sınıfı *"), selection: $workplaces[index].hazardClass)
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.isyeri.adresi.9516bba5", table: .localizable, fallback: "İşyeri adresi"), symbol: "mappin.and.ellipse", text: $workplaces[index].address, id: "workplace-\(index)-address")
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.isyeri.sehri.8120f703", table: .localizable, fallback: "İşyeri şehri"), symbol: "map", text: $workplaces[index].city, id: "workplace-\(index)-city")
                            }
                            if index < workplaces.count - 1 { Divider() }
                        }
                        Button { workplaces.append(.init()) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text(RDLocalization.string("localizable.nova.pilot.company.create.view.baska.isyeri.ekle.eda3cf83", table: .localizable, fallback: "Başka işyeri ekle")).font(NovaFont.font(.bodyStrong))
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        }.buttonStyle(NovaRowPressStyle())
                    }
                }
            }
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(RDLocalization.string("localizable.nova.pilot.company.create.view.firmaya.departman.eklemek.ister.misiniz.d461a27e", table: .localizable, fallback: "Firmaya departman eklemek ister misiniz?"), isOn: departmentToggle).tint(NovaColorToken.accent.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.pilot.company.create.view.orn.boyahane.imalat.48c8ed81", table: .localizable, fallback: "Örn. boyahane, imalat"), style: .metaQuiet)
                    if !departments.isEmpty {
                        ForEach(departments.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.departman.adi.1effe541", table: .localizable, fallback: "Departman adı *"), symbol: "square.grid.2x2", text: $departments[index], id: "department-\(index)")
                                if index > 0 {
                                    Button { departments.remove(at: index) } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                                            .frame(width: 32, height: 32)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Button { departments.append("") } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text(RDLocalization.string("localizable.nova.pilot.company.create.view.baska.departman.ekle.4991f0f8", table: .localizable, fallback: "Başka departman ekle")).font(NovaFont.font(.bodyStrong))
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        }.buttonStyle(NovaRowPressStyle())
                    }
                }
            }
        }
        .disabled(!loaded || submitting || storageFailed)
    }

    private var responsibleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(RDLocalization.string("localizable.nova.pilot.company.create.view.sorumlu.iletisim.personeli.eklemek.ister.misiniz.ae1010f5", table: .localizable, fallback: "Sorumlu & iletişim personeli eklemek ister misiniz?"), isOn: $addResponsible).tint(NovaColorToken.accent.color(in: scheme))
                    if addResponsible {
                        ForEach($contacts) { $contact in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    let index = contacts.firstIndex(where: { $0.id == contact.id }) ?? 0
                                    NovaText(text: "Sorumlu \(index + 1)", style: .label)
                                    Spacer()
                                    if index > 0 {
                                        Button { contacts.removeAll { $0.id == contact.id } } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                                                .frame(width: 32, height: 32)
                                        }.buttonStyle(.plain)
                                    }
                                }
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.ad.soyad.02a69355", table: .localizable, fallback: "Ad soyad *"), symbol: "person", text: $contact.name, id: "contact-\(contact.id)-name")
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.telefon.c38a18b2", table: .localizable, fallback: "Telefon *"), symbol: "phone", text: $contact.phone, id: "contact-\(contact.id)-phone", keyboard: .phonePad)
                                field(RDLocalization.string("localizable.nova.pilot.company.create.view.mail.adresi.9f7bd458", table: .localizable, fallback: "Mail adresi"), symbol: "envelope", text: $contact.email, id: "contact-\(contact.id)-email", keyboard: .emailAddress)
                                Picker(RDLocalization.string("localizable.nova.pilot.company.create.view.gorevi.e22dc2fb", table: .localizable, fallback: "Görevi *"), selection: $contact.role) {
                                    Text(RDLocalization.string("localizable.nova.pilot.company.create.view.gorev.secin.8e8d2068", table: .localizable, fallback: "Görev seçin")).tag("")
                                    ForEach(roles, id: \.self) { Text($0).tag($0) }
                                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 4)
                            if contact.id != contacts.last?.id { Divider() }
                        }
                        Button { contacts.append(.init()) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                Text(RDLocalization.string("localizable.nova.pilot.company.create.view.ek.personel.ekle.b20c56fe", table: .localizable, fallback: "Ek personel ekle")).font(NovaFont.font(.bodyStrong))
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        }.buttonStyle(NovaRowPressStyle())
                    }
                }
            }
        }
        .onChange(of: addResponsible) { enabled in if enabled && contacts.isEmpty { contacts = [.init()] } }
        .disabled(!loaded || submitting || storageFailed)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        NovaText(text: RDLocalization.string("localizable.nova.pilot.company.create.view.firma.ozeti.20f70c2a", table: .localizable, fallback: "Firma özeti"), style: .bodyStrong); Spacer()
                        Button(RDLocalization.string("localizable.nova.pilot.company.create.view.bilgileri.duzenle.05875265", table: .localizable, fallback: "Bilgileri düzenle")) { beginEditing() }
                            .font(NovaFont.font(.meta)).foregroundStyle(NovaColorToken.accent.color(in: scheme))
                    }
                    summaryRow("Firma", name, "building.2")
                    summaryRow("İletişim", [address, city, phone].filter { !$0.trimmed.isEmpty }.joined(separator: " · "), "mappin.and.ellipse")
                    summaryRow("İşletme", [hazard.title, sector, employeeCount.isEmpty ? nil : "\(employeeCount) çalışan"].compactMap { $0 }.joined(separator: " · "), "shield")
                    if !naceCode.trimmed.isEmpty || !workplaceRegistryNo.trimmed.isEmpty {
                        summaryRow("NACE / sicil", [naceCode, workplaceRegistryNo].filter { !$0.trimmed.isEmpty }.joined(separator: " · "), "doc.text")
                    }
                    ForEach(workplaces.indices, id: \.self) { index in
                        let workplace = workplaces[index]
                        summaryRow(RDLocalization.format("localizable.nova.pilot.company.create.view.isyeri.1.29e3c974", table: .localizable, fallback: "İşyeri %1$@", arguments: [String(describing: index + 1)]), [workplace.name, workplace.hazardClass.title, workplace.address, workplace.city]
                            .filter { !$0.trimmed.isEmpty }.joined(separator: " · "), "building.2")
                    }
                    ForEach(departments.indices, id: \.self) { index in
                        summaryRow("Departman \(index + 1)", departments[index], "square.grid.2x2")
                    }
                    if addResponsible {
                        ForEach(contacts.indices, id: \.self) { index in
                            let contact = contacts[index]
                            summaryRow("Sorumlu \(index + 1)", [contact.name, contact.role, contact.phone, contact.email]
                                .filter { !$0.trimmed.isEmpty }.joined(separator: " · "), "person")
                        }
                    }
                }
            }
            NovaHelpHint(text: RDLocalization.string("localizable.nova.pilot.company.create.view.firma.ekle.ile.kayit.tamamlanir.bilgiler.sonraki.2652d9a2", table: .localizable, fallback: "Firma Ekle ile kayıt tamamlanır; bilgiler sonraki modüllerde hazır olur."))
        }
    }

    private func summaryRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            NovaIcon(symbol: symbol, size: 17)
            VStack(alignment: .leading, spacing: 1) { NovaText(text: title, style: .metaQuiet); NovaText(text: value.isEmpty ? "Belirtilmedi" : value, style: .body) }
        }
    }

    private func beginEditing() {
        // Keep a staged request until submit so it can be replayed against the
        // same server row before the edited profile is persisted.
        error = nil
        step = 0
    }

    private func hazardPicker(title: String, selection: Binding<CompanyHazardClass>) -> some View {
        HStack(spacing: 10) {
            NovaIcon(symbol: "exclamationmark.triangle", size: 17)
            Picker(title, selection: selection) { ForEach(CompanyHazardClass.allCases) { Text($0.title).tag($0) } }
                .font(NovaFont.font(.body)).tint(NovaColorToken.text.color(in: scheme))
        }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }

    private func field(_ title: String, symbol: String, text: Binding<String>, id: String,
                       keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 10) {
            NovaIcon(symbol: symbol, size: 17).frame(width: 22)
            TextField(title, text: text, axis: title.localizedCaseInsensitiveContains("adres") ? .vertical : .horizontal)
                .lineLimit(title.localizedCaseInsensitiveContains("adres") ? 1...3 : 1...1)
                .font(NovaFont.font(.body)).keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled().focused($focusedField, equals: id).submitLabel(.done)
                .accessibilityLabel(title).accessibilityIdentifier("nova.pilot.company.\(id)")
        }.frame(minHeight: 40)
    }

    private func goBack() { guard !submitting else { return }; error = nil; if step > 0 { step -= 1 } else { dismiss() } }

    private func advance() {
        focusedField = nil; error = nil
        guard loaded, !storageFailed else { error = RDLocalization.string("localizable.nova.pilot.company.create.view.kayit.durumu.dogrulanamadi.lutfen.tekrar.deneyin.ac119622", table: .localizable, fallback: "Kayıt durumu doğrulanamadı. Lütfen tekrar deneyin."); return }
        guard canAdvance else {
            error = step == 1 ? RDLocalization.string("localizable.nova.pilot.company.create.view.tehlike.sinifi.sektor.ve.calisan.sayisi.zorunlud.e9a54d53", table: .localizable, fallback: "Tehlike sınıfı, sektör ve çalışan sayısı zorunludur.") : RDLocalization.string("localizable.nova.pilot.company.create.view.bu.adimdaki.zorunlu.alanlari.tamamlayin.bfed4d3e", table: .localizable, fallback: "Bu adımdaki zorunlu alanları tamamlayın.")
            return
        }
        if step < totalSteps - 1 { step += 1 } else { submitting = true }
    }

    private static func message(_ error: Error) -> String {
        if let error = error as? PostgrestError {
            switch error.message {
            case "company_limit_exceeded": return RDLocalization.string("localizable.nova.pilot.company.create.view.firma.limitinize.ulastiniz.5ac4ff54", table: .localizable, fallback: "Firma limitinize ulaştınız.")
            case "PAID_PLAN_REQUIRED": return RDLocalization.string("localizable.nova.pilot.company.create.view.firma.olusturma.erisimi.dogrulanamadi.lutfen.tek.4846b605", table: .localizable, fallback: "Firma oluşturma erişimi doğrulanamadı. Lütfen tekrar deneyin.")
            case "FEATURE_UNAVAILABLE", "ACCESS_DENIED": return RDLocalization.string("localizable.nova.pilot.company.create.view.pilot.yazma.erisimi.acik.degil.veya.suresi.dolmu.69e73a00", table: .localizable, fallback: "Pilot yazma erişimi açık değil veya süresi dolmuş.")
            case "IDEMPOTENCY_CONFLICT": return RDLocalization.string("localizable.nova.pilot.company.create.view.bekleyen.islemin.icerigi.uyusmuyor.yeni.kayit.ac.2532144b", table: .localizable, fallback: "Bekleyen işlemin içeriği uyuşmuyor. Yeni kayıt açılmadı.")
            default: break
            }
        }
        return RDLocalization.string("localizable.nova.pilot.company.create.view.islemin.sonucu.dogrulanamadi.baglantinizi.kontro.52ae5e3a", table: .localizable, fallback: "İşlemin sonucu doğrulanamadı. Bağlantınızı kontrol edip aynı kaydı tekrar deneyin.")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
