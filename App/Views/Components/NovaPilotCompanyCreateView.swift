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

    private let roles = ["Firma Sahibi", "Firma Müdürü", "Bölüm Sorumlusu", "İş Güvenliği Uzmanı", "İnsan Kaynakları", "İdari İşler", "Diğer"]
    private var totalSteps: Int { 5 }
    private var stepTitles: [String] { ["Firma bilgileri", "İşletme bilgileri", "İşyeri ve departman", "Sorumlu & iletişim", "Firma özeti"] }
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
                NovaTaskSuccessView(title: "Firma oluşturuldu",
                    message: "Firma bilgileri kaydedildi ve ilgili modüllerde kullanılmaya hazır.",
                    doneTitle: "Firmaya git", onDone: { dismiss() })
            } else {
                NovaPageSurface(onEdgeBack: goBack) {
                    VStack(spacing: 0) {
                        NovaTaskHeader(title: "Firma ekle", step: step + 1, total: totalSteps,
                            stepTitle: stepTitles[step], onClose: goBack)
                            .padding(.horizontal, 18).padding(.top, 8)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                stepContent
                                if pending != nil {
                                    NovaText(text: "Bekleyen işlem bulundu. Aynı kayıt tekrar gönderilebilir; yeni bir firma oluşturulmaz.", style: .metaQuiet)
                                }
                                if let error { NovaTaskErrorSummary(message: error) }
                            }
                            .padding(20).padding(.bottom, 12)
                            .background { Color.clear.contentShape(Rectangle()).onTapGesture { focusedField = nil } }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == totalSteps - 1 ? "Firma Ekle" : "Devam",
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
                    contacts = [.init(name: person, phone: pending.responsiblePhone ?? "", email: pending.responsibleEmail ?? "", role: "Diğer")]
                }
            }
            loaded = true
        } catch {
            storageFailed = true
            self.error = "Bekleyen kayıt güvenle okunamadı. Kaydı çoğaltmamak için işlem durduruldu."
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
            NovaHelpHint(text: "Firma bilgileri bir kez seçilir; sonraki modül kayıtlarına otomatik taşınır.")
            NovaCard(padding: 16) {
                VStack(spacing: 10) {
                    field("Firma adı *", symbol: "building.2", text: $name, id: "name")
                    Divider(); field("Adres", symbol: "mappin.and.ellipse", text: $address, id: "address")
                    Divider(); field("Şehir", symbol: "map", text: $city, id: "city")
                    Divider(); field("Firma telefonu", symbol: "phone", text: $phone, id: "phone", keyboard: .phonePad)
                }
            }
        }
        .disabled(!loaded || submitting || storageFailed)
    }

    private var businessStep: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                hazardPicker(title: "Tehlike sınıfı *", selection: $hazard)
                Divider(); field("Sektör *", symbol: "square.grid.2x2", text: $sector, id: "sector")
                Divider(); field("Çalışan sayısı *", symbol: "person.2", text: $employeeCount, id: "employeeCount", keyboard: .numberPad)
                Divider(); field("NACE kodu", symbol: "number", text: $naceCode, id: "nace")
                Divider(); field("İşyeri sicil no", symbol: "doc.text", text: $workplaceRegistryNo, id: "registry")
            }
        }
        .disabled(!loaded || submitting || storageFailed)
    }

    private var workplaceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Aynı firmaya ait farklı işyeri var mı?", isOn: workplaceToggle).tint(NovaColorToken.accent.color(in: scheme))
                    if !workplaces.isEmpty {
                        ForEach(workplaces.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    NovaText(text: "İşyeri \(index + 1)", style: .label)
                                    Spacer()
                                    if index > 0 {
                                        Button { workplaces.remove(at: index) } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                                                .frame(width: 32, height: 32)
                                        }.buttonStyle(.plain)
                                    }
                                }
                                field("İşyeri adı *", symbol: "building.2", text: $workplaces[index].name, id: "workplace-\(index)-name")
                                hazardPicker(title: "İşyeri tehlike sınıfı *", selection: $workplaces[index].hazardClass)
                                field("İşyeri adresi", symbol: "mappin.and.ellipse", text: $workplaces[index].address, id: "workplace-\(index)-address")
                                field("İşyeri şehri", symbol: "map", text: $workplaces[index].city, id: "workplace-\(index)-city")
                            }
                            if index < workplaces.count - 1 { Divider() }
                        }
                        Button { workplaces.append(.init()) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Başka işyeri ekle").font(NovaFont.font(.bodyStrong))
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        }.buttonStyle(NovaRowPressStyle())
                    }
                }
            }
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Firmaya departman eklemek ister misiniz?", isOn: departmentToggle).tint(NovaColorToken.accent.color(in: scheme))
                    NovaText(text: "Örn. boyahane, imalat", style: .metaQuiet)
                    if !departments.isEmpty {
                        ForEach(departments.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                field("Departman adı *", symbol: "square.grid.2x2", text: $departments[index], id: "department-\(index)")
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
                                Text("Başka departman ekle").font(NovaFont.font(.bodyStrong))
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
                    Toggle("Sorumlu & iletişim personeli eklemek ister misiniz?", isOn: $addResponsible).tint(NovaColorToken.accent.color(in: scheme))
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
                                field("Ad soyad *", symbol: "person", text: $contact.name, id: "contact-\(contact.id)-name")
                                field("Telefon *", symbol: "phone", text: $contact.phone, id: "contact-\(contact.id)-phone", keyboard: .phonePad)
                                field("Mail adresi", symbol: "envelope", text: $contact.email, id: "contact-\(contact.id)-email", keyboard: .emailAddress)
                                Picker("Görevi *", selection: $contact.role) {
                                    Text("Görev seçin").tag("")
                                    ForEach(roles, id: \.self) { Text($0).tag($0) }
                                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 4)
                            if contact.id != contacts.last?.id { Divider() }
                        }
                        Button { contacts.append(.init()) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                Text("Ek personel ekle").font(NovaFont.font(.bodyStrong))
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
                        NovaText(text: "Firma özeti", style: .bodyStrong); Spacer()
                        Button("Bilgileri düzenle") { beginEditing() }
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
                        summaryRow("İşyeri \(index + 1)", [workplace.name, workplace.hazardClass.title, workplace.address, workplace.city]
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
            NovaHelpHint(text: "Firma Ekle ile kayıt tamamlanır; bilgiler sonraki modüllerde hazır olur.")
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
        guard loaded, !storageFailed else { error = "Kayıt durumu doğrulanamadı. Lütfen tekrar deneyin."; return }
        guard canAdvance else {
            error = step == 1 ? "Tehlike sınıfı, sektör ve çalışan sayısı zorunludur." : "Bu adımdaki zorunlu alanları tamamlayın."
            return
        }
        if step < totalSteps - 1 { step += 1 } else { submitting = true }
    }

    private static func message(_ error: Error) -> String {
        if let error = error as? PostgrestError {
            switch error.message {
            case "company_limit_exceeded": return "Firma limitinize ulaştınız."
            case "PAID_PLAN_REQUIRED": return "Firma oluşturmak için aktif Plus veya Pro aboneliği gerekiyor."
            case "FEATURE_UNAVAILABLE", "ACCESS_DENIED": return "Pilot yazma erişimi açık değil veya süresi dolmuş."
            case "IDEMPOTENCY_CONFLICT": return "Bekleyen işlemin içeriği uyuşmuyor. Yeni kayıt açılmadı."
            default: break
            }
        }
        return "İşlemin sonucu doğrulanamadı. Bağlantınızı kontrol edip aynı kaydı tekrar deneyin."
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
