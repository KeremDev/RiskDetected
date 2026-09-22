import SwiftUI
import Foundation

/// Guided, tenant-scoped emergency-plan creation. It preserves the existing
/// mutation contract while replacing the former all-at-once popup form.
struct IsgWorkspaceEmergencyPlanCreateFlow: View {
    private enum Step: String, CaseIterable { case scope, dates, team, file, review }

    @ObservedObject var store: IsgWorkspaceStore
    let companyName: String
    let onDone: () -> Void

    @State private var currentStep: Step = .scope
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var workplaceID: UUID?
    @State private var scope = "Acil Durum Planı"
    @State private var preparedOn = Calendar.current.startOfDay(for: Date())
    @State private var validUntil = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var overridesValidity = false
    @State private var employeeQuery = ""
    @State private var selectedEmployees = Set<UUID>()
    @State private var roles: [UUID: String] = [:]
    @State private var note = ""
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var loading = true
    @State private var saving = false
    @State private var validationError: String?
    @State private var error: String?
    @State private var confirmingExit = false
    @State private var didSave = false
    @State private var draftSaved = false
    @State private var workflowMutationIDs: [String: UUID] = [:]
    @Environment(\.novaCelebrate) private var celebrate

    private var stepNumber: Int { (Step.allCases.firstIndex(of: currentStep) ?? 0) + 1 }
    private var filteredEmployees: [IsgWorkspaceEmployeeEntry] {
        let needle = employeeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return employees }
        return employees.filter {
            $0.name.localizedCaseInsensitiveContains(needle) ||
            $0.code.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        Group {
            if didSave {
                NovaTaskSuccessView(title: "Acil durum planı kaydedildi",
                    message: selectedEmployees.isEmpty
                        ? "Plan ve geçerlilik tarihi firma kaydına eklendi. Acil durum ekibini daha sonra ekleyebilirsiniz."
                        : "Plan, geçerlilik tarihi ve \(selectedEmployees.count) kişilik ekip firma kaydına eklendi. Sıradaki mantıklı işlem bir tatbikat planlamaktır.",
                    doneTitle: "Planlara dön", onDone: onDone)
            } else {
                NovaPageSurface {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            NovaTaskHeader(title: "Acil durum planı ekle", step: stepNumber,
                                total: Step.allCases.count, stepTitle: stepTitle(currentStep)) {
                                    confirmingExit = true
                                }
                            if loading {
                                NovaLoadingView(message: "İşyeri ve personel bilgileri hazırlanıyor…")
                            } else {
                                if let validationError { NovaTaskErrorSummary(message: validationError) }
                                stepContent(currentStep)
                                if let error { NovaTaskErrorSummary(message: error) }
                            }
                        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 28)
                            .novaAsyncContent(isLoading: loading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        if !loading {
                            NovaTaskStickyActions(primaryTitle: currentStep == .review ? "Yayımla" : "Devam",
                                primarySymbol: currentStep == .review ? "checkmark.seal" : "arrow.right",
                                isWorking: saving, canGoBack: currentStep != .scope,
                                onBack: previousStep, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .task { await prepare() }
        .onChange(of: preparedOn) { _ in refreshAutomaticValidity() }
        .onChange(of: overridesValidity) { enabled in if !enabled { refreshAutomaticValidity() } }
        .confirmationDialog("Plan akışından çıkılsın mı?", isPresented: $confirmingExit,
            titleVisibility: .visible) {
                Button("Çık", role: .destructive, action: onDone)
                Button("Devam et", role: .cancel) {}
            } message: { Text("Henüz kaydedilmemiş bilgiler silinir.") }
    }

    @ViewBuilder private func stepContent(_ step: Step) -> some View {
        switch step {
        case .scope: scopeStep
        case .dates: datesStep
        case .team: teamStep
        case .file: fileStep
        case .review: reviewStep
        }
    }

    private var scopeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaFormValueRow(label: "Firma", symbol: "building.2") {
                NovaText(text: companyName, style: .bodyStrong)
            }
            if workplaces.count == 1 {
                NovaFormValueRow(label: "İşyeri", symbol: "mappin.and.ellipse") {
                    NovaText(text: workplaces[0].name, style: .bodyStrong)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: "İşyeri", style: .metaQuiet)
                    Picker("İşyeri", selection: $workplaceID) {
                        Text("İşyeri seçin").tag(Optional<UUID>.none)
                        ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu)
                }.padding(12).novaControlBackground(cornerRadius: 14)
            }
            labeledField("Plan kapsamı", text: $scope)
        }
    }

    private var datesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            dateField("Hazırlama tarihi", selection: $preparedOn)
            if overridesValidity {
                dateField("Geçerlilik tarihi", selection: $validUntil)
            } else {
                NovaFormValueRow(label: "Geçerlilik", symbol: "calendar.badge.clock") {
                    VStack(alignment: .trailing, spacing: 2) {
                        NovaText(text: Self.day(validUntil), style: .bodyStrong)
                        NovaText(text: "Otomatik hesaplandı", style: .micro)
                    }
                }
            }
            Toggle("Geçerlilik tarihini değiştir", isOn: $overridesValidity)
                .padding(12).novaControlBackground(cornerRadius: 14)
            NovaWhyDisclosure {
                NovaText(text: "Varsayılan tarih hazırlanma tarihinden bir yıl sonrası olarak hesaplanır. Yalnız istisna varsa değiştirin.", style: .metaQuiet)
            }
        }
    }

    private var teamStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NovaText(text: "Acil durum ekibi", style: .sectionTitle)
                Spacer()
                NovaText(text: "\(selectedEmployees.count) seçili", style: .metaQuiet)
            }
            NovaHelpHint(text: "Ekip eklemek isteğe bağlıdır. Şimdi kişi seçebilir veya bu adımı boş geçip ekibi daha sonra tamamlayabilirsiniz.")
            searchField
            if !employees.isEmpty {
                NovaCompactActionButton(title: selectedEmployees.count == employees.count ? "Seçimi temizle" : "Tümünü seç",
                    symbol: selectedEmployees.count == employees.count ? "xmark.circle" : "checkmark.circle") {
                        if selectedEmployees.count == employees.count {
                            selectedEmployees.removeAll(); roles.removeAll()
                        } else {
                            selectedEmployees = Set(employees.map(\.id))
                            for employee in employees { roles[employee.id] = roles[employee.id] ?? "other" }
                        }
                    }
            }
            if filteredEmployees.isEmpty {
                NovaEmptyState(title: employees.isEmpty ? "Firma personeli bulunmuyor" : "Eşleşen personel yok",
                    message: employees.isEmpty ? "Plan ekibine kişi seçmek için önce firma personeli ekleyin." : "Farklı bir ad veya personel kodu arayın.")
            }
            ForEach(filteredEmployees) { employee in
                VStack(alignment: .leading, spacing: 7) {
                    Button { toggle(employee.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedEmployees.contains(employee.id) ? "checkmark.circle.fill" : "circle")
                            NovaText(text: employee.name, style: .body)
                            Spacer(minLength: 0)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(NovaRowPressStyle())
                    if selectedEmployees.contains(employee.id) {
                        Picker("Ekip görevi", selection: roleBinding(employee.id)) {
                            ForEach(["coordinator", "fire", "first_aid", "evacuation", "other"], id: \.self) {
                                Text(IsgWorkspaceDisplayText.value($0)).tag($0)
                            }
                        }.pickerStyle(.menu).padding(.leading, 30)
                    }
                }.padding(.horizontal, 12).novaControlBackground(cornerRadius: 14)
            }
        }
    }

    private var fileStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: "Plan dosyası", style: .sectionTitle)
            IsgWorkspaceInlineAttachmentField(title: "PDF veya fotoğraf ekle (isteğe bağlı)", attachment: $attachment)
            DisclosureGroup("Ek bilgiler") {
                labeledField("Plan notu (isteğe bağlı)", text: $note).padding(.top, 8)
            }.font(NovaFont.font(.bodyStrong)).padding(12).novaControlBackground(cornerRadius: 14)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaText(text: "Kaydetmeden önce kontrol edin", style: .sectionTitle)
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    reviewRow("Firma", companyName)
                    reviewRow("İşyeri", workplaces.first(where: { $0.id == workplaceID })?.name ?? "Belirtilmedi")
                    reviewRow("Kapsam", clean(scope))
                    reviewRow("Hazırlama", Self.day(preparedOn))
                    reviewRow("Geçerlilik", Self.day(validUntil))
                    reviewRow("Ekip", "\(selectedEmployees.count) kişi")
                    reviewRow("Dosya", attachment?.filename ?? "Daha sonra eklenebilir")
                }
            }
            NovaButton(label: draftSaved ? "Taslak kaydedildi" : "Taslak olarak kaydet",
                symbol: draftSaved ? "checkmark" : "tray.and.arrow.down", variant: .surface,
                isEnabled: !draftSaved) {
                    // The workspace task deliberately keeps this draft in the
                    // current task until the server exposes a dedicated draft
                    // mutation. It is never sent as `publish` by this action.
                    saveDraft()
                    validationError = nil
                }.accessibilityIdentifier("osgb.emergency.form.save-draft")
            NovaText(text: "Taslak yayımlanmaz; yayımlamak için aşağıdaki ana aksiyonu kullanın.", style: .metaQuiet)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("Personel ara", text: $employeeQuery)
            if !employeeQuery.isEmpty {
                Button { employeeQuery = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .buttonStyle(NovaRowPressStyle()).accessibilityLabel("Aramayı temizle")
            }
        }.padding(.horizontal, 12).frame(minHeight: 48).novaControlBackground(cornerRadius: 14)
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: label, style: .metaQuiet)
            TextField(label, text: text, axis: .vertical).lineLimit(1...4).font(NovaFont.font(.body))
        }.padding(12).novaControlBackground(cornerRadius: 14)
    }

    private func dateField(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: label, style: .metaQuiet)
            DatePicker(label, selection: selection, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .novaControlBackground(cornerRadius: 14)
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .metaQuiet)
            NovaText(text: value, style: .bodyStrong)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepTitle(_ step: Step) -> String {
        switch step {
        case .scope: return "Kapsam"
        case .dates: return "Tarih ve geçerlilik"
        case .team: return "Acil durum ekibi"
        case .file: return "Plan dosyası"
        case .review: return "Kontrol ve kaydet"
        }
    }

    private func isComplete(_ step: Step) -> Bool {
        switch step {
        case .scope: return workplaceID != nil && !clean(scope).isEmpty
        case .dates: return validUntil > preparedOn
        case .team: return true
        case .file: return true
        case .review: return [.scope, .dates].allSatisfy(isComplete)
        }
    }

    private func validationMessage(_ step: Step) -> String {
        switch step {
        case .scope: return "İşyeri ve plan kapsamını belirtin."
        case .dates: return "Geçerlilik tarihi hazırlama tarihinden sonra olmalı."
        case .team: return "Ekip seçimi isteğe bağlıdır; devam edebilirsiniz."
        case .file: return "Dosya adımını kontrol edin."
        case .review: return "Önceki adımlarda tamamlanmamış bilgi var."
        }
    }

    private func advance() {
        validationError = nil
        guard isComplete(currentStep) else { validationError = validationMessage(currentStep); return }
        guard currentStep != .review else { save(); return }
        guard let index = Step.allCases.firstIndex(of: currentStep) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index + 1] }
    }

    private func previousStep() {
        validationError = nil
        guard let index = Step.allCases.firstIndex(of: currentStep), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index - 1] }
    }

    private func toggle(_ id: UUID) {
        if selectedEmployees.contains(id) { selectedEmployees.remove(id); roles.removeValue(forKey: id) }
        else { selectedEmployees.insert(id); roles[id] = roles[id] ?? "coordinator" }
    }

    private func roleBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { roles[id] ?? "coordinator" }, set: { roles[id] = $0 })
    }

    private func refreshAutomaticValidity() {
        guard !overridesValidity else { return }
        validUntil = Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: preparedOn)
            ?? Calendar.current.date(byAdding: .year, value: 1, to: preparedOn) ?? preparedOn
    }

    @MainActor private func prepare() async {
        loading = true; error = nil
        do {
            async let places = store.directory(.workplace)
            async let people = store.employees()
            (workplaces, employees) = try await (places, people)
            workplaceID = workplaces.first?.id
            refreshAutomaticValidity()
            restoreDraft()
        } catch {
            self.error = "İşyeri veya personel bilgileri yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }

    private var draftStorageKey: String? {
        workplaceID.map { "isg.workspace.emergency.draft.\($0.uuidString.lowercased())" }
    }

    /// Drafts are local working material until the workspace API exposes a
    /// dedicated draft mutation. The workplace UUID keeps tenants isolated.
    private func saveDraft() {
        guard let key = draftStorageKey else { return }
        let payload: [String: Any] = [
            "scope": scope, "preparedOn": Self.day(preparedOn),
            "validUntil": Self.day(validUntil), "note": note,
            "selectedEmployees": selectedEmployees.map(\.uuidString),
            "roles": roles.reduce(into: [String: String]()) { $0[$1.key.uuidString] = $1.value }
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        UserDefaults.standard.set(data, forKey: key)
        draftSaved = true
    }

    private func restoreDraft() {
        guard let key = draftStorageKey,
              let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let value = payload["scope"] as? String { scope = value }
        if let value = payload["preparedOn"] as? String, let date = Self.parseDay(value) { preparedOn = date }
        if let value = payload["validUntil"] as? String, let date = Self.parseDay(value) { validUntil = date }
        if let value = payload["note"] as? String { note = value }
        if let values = payload["selectedEmployees"] as? [String] {
            selectedEmployees = Set(values.compactMap(UUID.init(uuidString:)))
        }
        if let rawRoles = payload["roles"] as? [String: String] {
            roles = rawRoles.reduce(into: [UUID: String]()) { result, entry in
                if let id = UUID(uuidString: entry.key) { result[id] = entry.value }
            }
        }
        draftSaved = true
    }

    private static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func save() {
        guard isComplete(.review), let workplaceID else { return }
        let team: [IsgWorkspaceRPCValue] = selectedEmployees.sorted { $0.uuidString < $1.uuidString }.map { id in
            .object(["employee_id": .id(id), "role": .string(roles[id] ?? "coordinator"), "contact": .string("")])
        }
        let payload: [String: IsgWorkspaceRPCValue] = [
            "entity": .string("plan"), "action": .string("publish"), "workplace_id": .id(workplaceID),
            "scope": .string(clean(scope)), "prepared_on": .string(Self.day(preparedOn)),
            "valid_until": .string(Self.day(validUntil)), "review_note": .string(clean(note)),
            "team": .array(team)
        ]
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let created = try await store.mutateDomain(
                    mutationID: workflowID("emergency.create", payload), domain: .emergencyPlan, payload: payload)
                if let uploaded, let id = created.recordID {
                    _ = try await store.attachFile(
                        mutationID: workflowID("emergency.file.attach", ["entry_id": .id(uploaded.entryID), "parent_id": .id(id)]),
                        entryID: uploaded.entryID, parentKind: "emergency_plan", parentID: id, fieldName: "attachment")
                }
                celebrate(NovaSuccessMessage.recordSaved("Acil durum planı"))
                if let key = draftStorageKey { UserDefaults.standard.removeObject(forKey: key) }
                didSave = true
            } catch {
                self.error = "Plan kaydedilemedi. İşyeri ve tarih bilgilerini kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }

    private func uploadAttachmentIfNeeded() async throws -> IsgWorkspaceFileUploadResult? {
        guard let attachment else { return nil }
        return try await store.uploadFile(
            mutationID: workflowID("emergency.file.upload", [
                "filename": .string(attachment.filename),
                "digest": .string(IsgWorkspaceMutationAttempt.digest(attachment.data))
            ]), title: attachment.title, filename: attachment.filename,
            category: "emergency_plan", data: attachment.data)
    }

    private func workflowID(_ namespace: String, _ payload: [String: IsgWorkspaceRPCValue]) -> UUID {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(IsgWorkspaceRPCValue.object(payload))) ?? Data()
        let key = namespace + ":" + IsgWorkspaceMutationAttempt.digest(data)
        if let id = workflowMutationIDs[key] { return id }
        let id = UUID(); workflowMutationIDs[key] = id; return id
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
