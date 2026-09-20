import SwiftUI

/// Compact create surface for the primary D2-D6 records. Every command is
/// scoped by `IsgWorkspaceStore`; this view never calls a personal service.
struct IsgWorkspaceDomainCreateEditor: View {
    private enum FormSection: String { case record, attachment }
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    let onDone: () -> Void
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var plans: [IsgWorkspaceDomainRecord] = []
    @State private var riskAssessments: [IsgWorkspaceDomainRecord] = []
    @State private var checklistTemplates: [IsgWorkspaceChecklistTemplate] = []
    @State private var checklistTemplateID: String?
    @State private var workplaceID: UUID?
    @State private var employeeID: UUID?
    @State private var selectedEmployeeIDs = Set<UUID>()
    @State private var emergencyRoles: [UUID: String] = [:]
    @State private var employeeQuery = ""
    @State private var planID: UUID?
    @State private var primary = ""
    @State private var secondary = ""
    @State private var notes = ""
    @State private var option = ""
    @State private var location = ""
    @State private var hasValidity = false
    @State private var overridesAutomaticValidity = false
    @State private var hasEndDate = false
    @State private var boardState = "held"
    @State private var initialDecisions = ""
    @State private var number = 1
    @State private var firstDate = Date()
    @State private var secondDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @State private var workflowMutationIDs: [String: UUID] = [:]
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var openSection: FormSection? = .record
    @Environment(\.novaCelebrate) private var celebrate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: String(format: RDLocalization.string(
                    "localizable.nova.workspace.domain.add", table: .localizable,
                    fallback: "%@ ekle"), domain.title), symbol: domain.symbol,
                    subtitle: RDLocalization.string("localizable.nova.workspace.domain.create.scope",
                        table: .localizable, fallback: "Kayıt seçili firma kapsamında oluşturulur."))
                if loading {
                    NovaLoadingView(message: RDLocalization.string("localizable.nova.workspace.domain.form.loading",
                        table: .localizable, fallback: "Form hazırlanıyor…"))
                } else {
                    form
                    if let error { NovaHelpHint(text: error) }
                    NovaCompactActionButton(title: saving ? RDLocalization.string(
                        "localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…") :
                        saveTitle,
                        symbol: "checkmark", prominent: true, enabled: canSave && !saving) { save() }
                }
            }.padding(18).novaPopupContentSize()
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await prepare() }
        .onChange(of: firstDate) { _ in refreshAutomaticValidity() }
        .onChange(of: overridesAutomaticValidity) { _ in refreshAutomaticValidity() }
    }

    @ViewBuilder private var form: some View {
        if usesAccordion {
            createAccordion(.record, title: "Kayıt bilgileri", symbol: domain.symbol) {
                recordFields
            }
            createAccordion(.attachment, title: "Dosya ve kanıt", symbol: "doc.badge.plus") {
                attachmentField
            }
        } else {
            recordFields
            attachmentField
        }
    }

    @ViewBuilder private var recordFields: some View {
        if needsWorkplace { workplacePicker }
        if needsEmployee { employeePicker }
        if domain == .drill { planPicker }
        switch domain {
        case .training:
            trainingForm
        case .risk:
            riskForm
        case .nonconformity:
            textField(primaryLabel, text: $primary)
                optionPicker(label: optionLabel, values: ["low", "medium", "high", "critical"])
                datePicker(firstDateLabel, selection: $firstDate)
                datePicker(secondDateLabel, selection: $secondDate)
        case .checklist:
            if checklistTemplates.isEmpty {
                NovaEmptyState(title: label("localizable.nova.workspace.checklist.template.empty", "Yayımlanmış şablon yok"),
                               message: label("localizable.nova.workspace.checklist.template.empty.detail",
                                              "Kontrol listesi oluşturmak için önce onaylı bir şablon yayımlanmalıdır."))
            } else {
                Picker(label("localizable.nova.workspace.form.template", "Kontrol listesi şablonu"),
                       selection: $checklistTemplateID) {
                    ForEach(checklistTemplates) { template in
                        Text("\(template.title) · \(template.itemCount) madde")
                            .tag(Optional(template.id))
                    }
                }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
            }
            datePicker(firstDateLabel, selection: $firstDate)
        case .emergencyPlan:
            emergencyPlanForm
        case .drill:
            datePicker(firstDateLabel, selection: $firstDate)
        case .appointment:
            appointmentForm
        case .ppe:
            textField(primaryLabel, text: $primary)
            numberField(numberLabel)
            optionPicker(label: optionLabel, values: ["piece", "pair", "set", "metre", "litre"])
            datePicker(firstDateLabel, selection: $firstDate)
            textField(secondaryLabel, text: $secondary)
        case .equipment:
            textField(primaryLabel, text: $primary)
            textField(secondaryLabel, text: $secondary)
            datePicker(firstDateLabel, selection: $firstDate)
            textField(notesLabel, text: $notes)
        case .katip:
            textField(primaryLabel, text: $primary)
            textField(secondaryLabel, text: $secondary)
            textField(notesLabel, text: $notes)
            datePicker(firstDateLabel, selection: $firstDate)
            datePicker(secondDateLabel, selection: $secondDate)
            numberField(numberLabel)
        case .annualPlan:
            datePicker(firstDateLabel, selection: $firstDate)
        case .board:
            boardForm
        case .workPermit:
            textField(primaryLabel, text: $primary)
            textField(secondaryLabel, text: $secondary)
            textField(notesLabel, text: $notes)
            datePicker(firstDateLabel, selection: $firstDate, components: [.date, .hourAndMinute])
            datePicker(secondDateLabel, selection: $secondDate, components: [.date, .hourAndMinute])
        case .visit:
            textField(primaryLabel, text: $primary)
            textField(secondaryLabel, text: $secondary)
            textField(notesLabel, text: $notes)
            datePicker(firstDateLabel, selection: $firstDate)
        case .personnel, .files:
            EmptyView()
        }
    }

    private func createAccordion<Content: View>(_ section: FormSection, title: String, symbol: String,
                                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        NovaCompanyAccordion(title: title, symbol: symbol,
            identifier: "workspace.\(domain.rawValue).create.\(section.rawValue)",
            expanded: Binding(get: { openSection == section },
                              set: { openSection = $0 ? section : nil })) {
            content()
        }
    }

    private var attachmentField: some View {
        IsgWorkspaceInlineAttachmentField(
            title: "Bu kayda dosya ekle (isteğe bağlı)",
            attachment: $attachment)
    }

    private var workplacePicker: some View {
        Picker(RDLocalization.string("localizable.nova.workspace.personnel.workplace", table: .localizable,
            fallback: "İşyeri"), selection: $workplaceID) {
            ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private var employeePicker: some View {
        Picker(RDLocalization.string("localizable.nova.workspace.personnel.employee", table: .localizable,
            fallback: "Personel"), selection: $employeeID) {
            ForEach(employees) { Text($0.name).tag(Optional($0.id)) }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }

    private var trainingForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: "Eğitim bilgileri", style: .bodyStrong)
                    textField(primaryLabel, text: $primary)
                    textField(secondaryLabel, text: $secondary)
                    optionPicker(label: "Eğitim yöntemi", values: ["face_to_face", "online", "mixed"])
                    textField("Konum / toplantı bağlantısı", text: $location)
                }
            }
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: "Zaman ve süre", style: .bodyStrong)
                    compactDate("Eğitimin tamamlandığı tarih", selection: $firstDate)
                    numberField(numberLabel)
                    Toggle("Geçerlilik tarihi ekle", isOn: $hasValidity)
                        .padding(12).novaControlBackground(cornerRadius: 14)
                    if hasValidity { datePicker("Geçerlilik tarihi", selection: $secondDate) }
                }
            }
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        NovaText(text: "Katılımcılar", style: .bodyStrong)
                        Spacer()
                        NovaText(text: "\(selectedEmployeeIDs.count) seçili", style: .metaQuiet)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        TextField("Personel ara", text: $employeeQuery)
                    }.padding(.horizontal, 12).frame(minHeight: 44).novaControlBackground(cornerRadius: 14)
                    if filteredEmployees.isEmpty {
                        NovaHelpHint(text: employees.isEmpty
                            ? "Gerçekleşen eğitimi kaydetmek için önce firma personeli ekleyin."
                            : "Aramanızla eşleşen personel bulunamadı.")
                    } else {
                        ForEach(filteredEmployees) { employee in
                            Button {
                                if selectedEmployeeIDs.contains(employee.id) { selectedEmployeeIDs.remove(employee.id) }
                                else { selectedEmployeeIDs.insert(employee.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedEmployeeIDs.contains(employee.id)
                                          ? "checkmark.circle.fill" : "circle")
                                    NovaText(text: employee.name, style: .body)
                                    Spacer(minLength: 0)
                                }.frame(minHeight: 42).contentShape(Rectangle())
                            }.buttonStyle(NovaRowPressStyle())
                        }
                    }
                }
            }
            textField(notesLabel, text: $notes)
            NovaHelpHint(text: "Kaydettiğinizde seçilen personelin bu eğitime katıldığını beyan etmiş olursunuz. Ayrı planlama veya yoklama adımı yoktur.")
        }
    }

    private var riskForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: selectedRiskAssessment == nil ? "Değerlendirme bilgileri" : "Revizyon bilgileri",
                             style: .bodyStrong)
                    textField(primaryLabel, text: $primary)
                    compactDate(selectedRiskAssessment == nil ? "Değerlendirme tarihi" : "Revizyon tarihi",
                                selection: $firstDate)
                }
            }
            if selectedRiskAssessment != nil {
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        NovaText(text: "Değişiklik nedeni", style: .bodyStrong)
                        textField(label("localizable.nova.workspace.form.revision.reason", "Revizyon nedeni"), text: $notes)
                        NovaHelpHint(text: "Bu işyerinde yürürlükte bir değerlendirme bulunduğu için yeni bir revizyon taslağı oluşturulur.")
                    }
                }
            } else {
                NovaHelpHint(text: "İlk kayıt tam değerlendirme olarak açılır. Kaydettikten sonra geçerlilik süresini belirleyip kesinleştirebilirsiniz.")
            }
        }
    }

    private var emergencyPlanForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: "Plan tarihleri", style: .bodyStrong)
                    compactDate("Hazırlanma", selection: $firstDate)
                    Toggle("Otomatik geçerlilik tarihini değiştir", isOn: $overridesAutomaticValidity)
                        .padding(12).novaControlBackground(cornerRadius: 14)
                    if overridesAutomaticValidity {
                        compactDate("Geçerlilik", selection: $secondDate)
                    } else {
                        NovaFormValueRow(label: "Geçerlilik", symbol: "calendar.badge.clock") {
                            NovaText(text: Self.day(secondDate), style: .bodyStrong)
                        }
                    }
                    NovaHelpHint(text: overridesAutomaticValidity
                        ? "Uzman tarafından belirlenen tarih kullanılacak."
                        : "Geçerlilik hazırlanma tarihinden bir yıl sonrası olarak hesaplandı; gerekirse değiştirebilirsiniz.")
                }
            }
            multiEmployeeSelector(title: "Acil durum ekibi", showsRoles: true)
            textField("Plan notu (isteğe bağlı)", text: $notes)
        }
    }

    private var appointmentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            singleEmployeeSelector
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: "Görev", style: .bodyStrong)
                    optionPicker(label: "Görev türü",
                                 values: ["representative", "support_staff", "team_member", "first_aid", "fire_team"])
                    HStack(alignment: .top, spacing: 8) {
                        compactDate("Başlangıç", selection: $firstDate)
                        if hasEndDate { compactDate("Bitiş", selection: $secondDate) }
                    }
                    Toggle("Bitiş tarihi belirle", isOn: $hasEndDate)
                        .padding(12).novaControlBackground(cornerRadius: 14)
                }
            }
            NovaHelpHint(text: "Çalışan temsilcisi ve destek elemanı kayıtları beyana dayanır; uygulama yeterlilik veya zorunlu kişi sayısı doğrulaması yapmaz.")
        }
    }

    private var boardForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: "Toplantı", style: .bodyStrong)
                    compactDate("Toplantı tarihi", selection: $firstDate)
                    Picker("Durum", selection: $boardState) {
                        Text("Gerçekleşti").tag("held")
                        Text("İptal edildi").tag("cancelled")
                    }.pickerStyle(.segmented)
                    textField("Gündem maddeleri · her satıra bir madde", text: $primary)
                }
            }
            if boardState == "held" {
                multiEmployeeSelector(title: "Katılımcılar", showsRoles: false)
                textField("Alınan kararlar · her satıra bir karar", text: $initialDecisions)
            } else {
                textField("İptal gerekçesi", text: $notes)
            }
            NovaHelpHint(text: "Kurul toplantısı mevzuat kapsamındaki gerçekleşen kayıt olarak saklanır; kararlar toplantıya bağlı ayrı takip maddelerine dönüşür.")
        }
    }

    private var singleEmployeeSelector: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    NovaText(text: "Personel", style: .bodyStrong)
                    Spacer()
                    if employeeID != nil { NovaText(text: "1 seçili", style: .metaQuiet) }
                }
                employeeSearchField
                ForEach(filteredEmployees) { employee in
                    Button { employeeID = employee.id } label: {
                        HStack(spacing: 10) {
                            Image(systemName: employeeID == employee.id ? "checkmark.circle.fill" : "circle")
                            NovaText(text: employee.name, style: .body)
                            Spacer(minLength: 0)
                        }.frame(minHeight: 42).contentShape(Rectangle())
                    }.buttonStyle(NovaRowPressStyle())
                }
            }
        }
    }

    private func multiEmployeeSelector(title: String, showsRoles: Bool) -> some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    NovaText(text: title, style: .bodyStrong)
                    Spacer()
                    NovaText(text: "\(selectedEmployeeIDs.count) seçili", style: .metaQuiet)
                }
                employeeSearchField
                if filteredEmployees.isEmpty {
                    NovaHelpHint(text: employees.isEmpty ? "Önce firma personeli ekleyin." : "Aramanızla eşleşen personel bulunamadı.")
                }
                ForEach(filteredEmployees) { employee in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            if selectedEmployeeIDs.contains(employee.id) {
                                selectedEmployeeIDs.remove(employee.id)
                                emergencyRoles.removeValue(forKey: employee.id)
                            } else {
                                selectedEmployeeIDs.insert(employee.id)
                                if showsRoles { emergencyRoles[employee.id] = emergencyRoles[employee.id] ?? "coordinator" }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedEmployeeIDs.contains(employee.id) ? "checkmark.circle.fill" : "circle")
                                NovaText(text: employee.name, style: .body)
                                Spacer(minLength: 0)
                            }.frame(minHeight: 42).contentShape(Rectangle())
                        }.buttonStyle(NovaRowPressStyle())
                        if showsRoles && selectedEmployeeIDs.contains(employee.id) {
                            Picker("Ekip görevi", selection: emergencyRoleBinding(employee.id)) {
                                ForEach(["coordinator", "fire", "first_aid", "evacuation", "other"], id: \.self) {
                                    Text(IsgWorkspaceDisplayText.value($0)).tag($0)
                                }
                            }.pickerStyle(.menu).padding(.leading, 30)
                        }
                    }
                }
            }
        }
    }

    private var employeeSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("Personel ara", text: $employeeQuery)
            if !employeeQuery.isEmpty {
                Button { employeeQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(NovaRowPressStyle())
            }
        }.padding(.horizontal, 12).frame(minHeight: 44).novaControlBackground(cornerRadius: 14)
    }

    private func emergencyRoleBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { emergencyRoles[id] ?? "coordinator" }, set: { emergencyRoles[id] = $0 })
    }

    private var filteredEmployees: [IsgWorkspaceEmployeeEntry] {
        let needle = employeeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return employees }
        return employees.filter { $0.name.localizedCaseInsensitiveContains(needle) ||
            $0.code.localizedCaseInsensitiveContains(needle) }
    }
    private var planPicker: some View {
        Picker(RDLocalization.string("localizable.nova.workspace.domain.plan", table: .localizable,
            fallback: "Acil durum planı"), selection: $planID) {
            ForEach(plans) { Text($0.title).tag(Optional($0.id)) }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func textField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text, axis: .vertical).lineLimit(1...4).font(NovaFont.font(.body))
            .padding(14).novaControlBackground(cornerRadius: 14)
    }
    private func datePicker(_ label: String, selection: Binding<Date>, components: DatePickerComponents = .date) -> some View {
        DatePicker(label, selection: selection, displayedComponents: components)
            .padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func compactDate(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: label, style: .metaQuiet)
            DatePicker(label, selection: selection, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .novaControlBackground(cornerRadius: 14)
    }
    private func numberField(_ label: String) -> some View {
        Stepper("\(label): \(number)", value: $number, in: 1...100_000)
            .padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func optionPicker(label: String, values: [String]) -> some View {
        Picker(label, selection: $option) {
            ForEach(values, id: \.self) { Text(optionTitle($0)).tag($0) }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }

    private var needsWorkplace: Bool {
        ![.training, .ppe].contains(domain)
    }
    private var needsEmployee: Bool {
        [.ppe].contains(domain)
    }
    private var usesAccordion: Bool {
        [.nonconformity, .emergencyPlan, .appointment, .ppe, .katip,
         .board, .workPermit, .visit].contains(domain)
    }

    private func refreshAutomaticValidity() {
        guard domain == .emergencyPlan, !overridesAutomaticValidity else { return }
        secondDate = Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: firstDate)
            ?? Calendar.current.date(byAdding: .year, value: 1, to: firstDate) ?? firstDate
    }
    private var canSave: Bool {
        if needsWorkplace && workplaceID == nil { return false }
        if needsEmployee && employeeID == nil { return false }
        if domain == .drill && planID == nil { return false }
        switch domain {
        case .training:
            return !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedEmployeeIDs.isEmpty &&
                Calendar.current.startOfDay(for: firstDate) <= Calendar.current.startOfDay(for: Date())
        case .nonconformity, .ppe, .equipment, .workPermit, .visit:
            return !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .emergencyPlan:
            return !selectedEmployeeIDs.isEmpty && secondDate > firstDate
        case .appointment:
            return employeeID != nil && (!hasEndDate || secondDate > firstDate)
        case .board:
            let hasAgenda = !lineValues(primary).isEmpty
            return hasAgenda && (boardState == "held" ? !selectedEmployeeIDs.isEmpty :
                notes.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5)
        case .risk:
            return !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (selectedRiskAssessment == nil || notes.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10)
        case .katip: return !primary.isEmpty && !secondary.isEmpty && !notes.isEmpty
        case .checklist: return selectedChecklistTemplate != nil
        case .personnel, .files: return false
        default: return true
        }
    }

    @MainActor private func prepare() async {
        loading = true; error = nil
        do {
            if needsWorkplace { workplaces = try await store.directory(.workplace); workplaceID = workplaces.first?.id }
            if needsEmployee { employees = try await store.employees(); employeeID = employees.first?.id }
            if [.training, .emergencyPlan, .appointment, .board].contains(domain) {
                employees = try await store.employees()
                if domain == .appointment { employeeID = nil }
                if domain == .training { firstDate = Calendar.current.startOfDay(for: Date()) }
            }
            if domain == .drill { plans = try await store.domain(.emergencyPlan).rows; planID = plans.first?.id }
            if domain == .risk { riskAssessments = try await store.domain(.risk).rows }
            if domain == .checklist {
                checklistTemplates = try await store.checklistTemplates()
                checklistTemplateID = checklistTemplates.first?.id
            }
            option = defaultOption
            number = domain == .training ? 60 : 1
            if domain == .emergencyPlan { primary = "Acil Durum Planı" }
        } catch {
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                                               fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        loading = false
    }

    private func save() {
        guard canSave else { return }
        if domain == .board { saveBoard(); return }
        if domain == .training { saveTraining(); return }
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let command = payload(assetID: uploaded?.assetID)
                var attempt = mutationAttempt
                let mutationID = attempt.id(namespace: "domain.\(domain.rawValue)", payload: command)
                mutationAttempt = attempt
                let created = try await store.mutateDomain(
                    mutationID: mutationID, domain: domain, payload: command)
                try await attach(uploaded, to: created.recordID)
                celebrate(NovaSuccessMessage.recordSaved(domain.title))
                onDone()
            } catch {
                self.error = RDLocalization.string("localizable.nova.workspace.mutation.failed", table: .localizable,
                    fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
            }
            saving = false
        }
    }

    /// The personal pilot stores a completed education record in one action.
    /// The workspace API has an internal draft transition, so complete it in
    /// the same idempotent workflow without exposing planning to the user.
    private func saveTraining() {
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let create = payload(assetID: uploaded?.assetID)
                let created = try await store.mutateDomain(
                    mutationID: workflowMutationID("training.create", payload: create),
                    domain: .training, payload: create)
                guard let trainingID = created.recordID, let createdVersion = created.version else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                let complete: [String: IsgWorkspaceRPCValue] = [
                    "action": .string("complete"), "id": .id(trainingID),
                    "expected_version": .number(Int(createdVersion)),
                    "participants": .array(selectedEmployeeIDs.sorted { $0.uuidString < $1.uuidString }.map {
                        .object(["id": .id($0), "attended": .bool(true)])
                    })
                ]
                _ = try await store.mutateDomain(
                    mutationID: workflowMutationID("training.complete", payload: complete),
                    domain: .training, payload: complete)
                try await attach(uploaded, to: trainingID)
                celebrate(NovaSuccessMessage.trainingSaved)
                onDone()
            } catch {
                self.error = "Eğitim kaydı tamamlanamadı. Tarih, süre ve katılımcıları kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }

    private func saveBoard() {
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let create = payload(assetID: uploaded?.assetID)
                let created = try await store.mutateDomain(
                    mutationID: workflowMutationID("board.create", payload: create),
                    domain: .board, payload: create)
                guard let meetingID = created.recordID, let createdVersion = created.version else {
                    throw IsgWorkspaceAPIFailure.invalidResponse
                }
                let outcome: [String: IsgWorkspaceRPCValue]
                if boardState == "held" {
                    outcome = ["kind": .string("board"), "action": .string("hold"),
                        "id": .id(meetingID), "expected_version": .number(Int(createdVersion)),
                        "held_on": .string(Self.day(firstDate)),
                        "attendance": .array(selectedEmployeeIDs.sorted { $0.uuidString < $1.uuidString }.map { .id($0) }),
                        "workspace_asset_id": uploaded.map { .id($0.assetID) } ?? .null]
                } else {
                    outcome = ["kind": .string("board"), "action": .string("cancel"),
                        "id": .id(meetingID), "expected_version": .number(Int(createdVersion)),
                        "reason": .string(notes.trimmingCharacters(in: .whitespacesAndNewlines))]
                }
                _ = try await store.mutateDomain(
                    mutationID: workflowMutationID("board.outcome", payload: outcome),
                    domain: .board, payload: outcome)

                if boardState == "held" {
                    for (offset, decision) in lineValues(initialDecisions).enumerated() {
                        let command: [String: IsgWorkspaceRPCValue] = [
                            "kind": .string("board_decision"), "action": .string("create"),
                            "meeting_id": .id(meetingID), "decision_no": .number(offset + 1),
                            "decision_text": .string(decision), "responsible_contact": .null, "due_on": .null
                        ]
                        _ = try await store.mutateDomain(
                            mutationID: workflowMutationID("board.decision.\(offset + 1)", payload: command),
                            domain: .board, payload: command)
                    }
                }
                try await attach(uploaded, to: meetingID)
                celebrate(NovaSuccessMessage.recordSaved("Kurul toplantısı"))
                onDone()
            } catch {
                self.error = "Toplantı kaydı tamamlanamadı. Gündem, katılımcı ve tarih bilgilerini kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }

    private func workflowMutationID(_ namespace: String,
                                    payload: [String: IsgWorkspaceRPCValue]) -> UUID {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(IsgWorkspaceRPCValue.object(payload))) ?? Data()
        let key = namespace + ":" + IsgWorkspaceMutationAttempt.digest(data)
        if let id = workflowMutationIDs[key] { return id }
        let id = UUID()
        workflowMutationIDs[key] = id
        return id
    }

    private func uploadAttachmentIfNeeded() async throws -> IsgWorkspaceFileUploadResult? {
        guard let attachment else { return nil }
        let signature: [String: IsgWorkspaceRPCValue] = [
            "filename": .string(attachment.filename),
            "digest": .string(IsgWorkspaceMutationAttempt.digest(attachment.data))
        ]
        return try await store.uploadFile(
            mutationID: workflowMutationID("\(domain.rawValue).file.upload", payload: signature),
            title: attachment.title, filename: attachment.filename,
            category: attachmentCategory, data: attachment.data)
    }

    private func attach(_ uploaded: IsgWorkspaceFileUploadResult?, to parentID: UUID?) async throws {
        guard let uploaded, let parentID, let parentKind = attachmentParentKind else { return }
        let signature: [String: IsgWorkspaceRPCValue] = [
            "entry_id": .id(uploaded.entryID), "parent_id": .id(parentID),
            "parent_kind": .string(parentKind)
        ]
        _ = try await store.attachFile(
            mutationID: workflowMutationID("\(domain.rawValue).file.attach", payload: signature),
            entryID: uploaded.entryID, parentKind: parentKind,
            parentID: parentID, fieldName: attachmentFieldName)
    }

    private func payload(assetID: UUID? = nil) -> [String: IsgWorkspaceRPCValue] {
        let place = IsgWorkspaceRPCValue.id(workplaceID)
        let employee = IsgWorkspaceRPCValue.id(employeeID)
        switch domain {
        case .training:
            let participants: [IsgWorkspaceRPCValue] = selectedEmployeeIDs.sorted { $0.uuidString < $1.uuidString }
                .map { .object(["id": .id($0), "attended": .bool(false)]) }
            return ["action": .string("save"), "expected_version": .number(0), "title": .string(primary),
                "trainer": .string(secondary), "method": .string(option),
                "starts_at": .string(Self.startOfDayInstant(firstDate)), "duration_minutes": .number(number),
                "valid_until": hasValidity ? .string(Self.day(secondDate)) : .null,
                "location": .string(location), "notes": .string(notes),
                "participants": .array(participants)]
        case .risk:
            let current = selectedRiskAssessment.flatMap { fact("current_version", in: $0) }.flatMap(Int.init) ?? 0
            let revision = selectedRiskAssessment != nil
            return ["action": .string("draft"), "workplace_id": place, "expected_current": .number(current),
                "kind": .string(revision ? "partial" : "full"), "assessment_on": .string(Self.day(firstDate)),
                "revision_on": revision ? .string(Self.day(firstDate)) : .null,
                "scope": .object(["summary": .string(primary)]),
                "reason": revision ? .string(notes.trimmingCharacters(in: .whitespacesAndNewlines)) : .null]
        case .nonconformity:
            return ["action": .string("create"), "workplace_id": place, "source_kind": .string("manual"),
                "source_ref": .null, "title": .string(primary), "severity": .string(option),
                "opened_on": .string(Self.day(firstDate)), "due_on": .string(Self.day(secondDate))]
        case .checklist:
            guard let template = selectedChecklistTemplate else { return [:] }
            return ["action": .string("create"), "workplace_id": place,
                "template_code": .string(template.code), "template_version": .number(template.version),
                "started_on": .string(Self.day(firstDate))]
        case .emergencyPlan:
            let team: [IsgWorkspaceRPCValue] = selectedEmployeeIDs.sorted { $0.uuidString < $1.uuidString }.map { id in
                .object(["employee_id": .id(id), "role": .string(emergencyRoles[id] ?? "coordinator"),
                         "contact": .string("")])
            }
            return ["entity": .string("plan"), "action": .string("publish"), "workplace_id": place,
                "scope": .string(primary), "prepared_on": .string(Self.day(firstDate)),
                "valid_until": .string(Self.day(secondDate)), "review_note": .string(notes),
                "team": .array(team)]
        case .drill:
            let version = plans.first(where: { $0.id == planID })?.version ?? 1
            return ["entity": .string("drill"), "action": .string("create"), "workplace_id": place,
                "plan_id": .id(planID), "plan_version": .number(Int(version)), "planned_on": .string(Self.day(firstDate))]
        case .appointment:
            return ["entity": .string("appointment"), "action": .string("create"), "employee_id": employee,
                "workplace_id": place, "kind": .string(option), "starts_on": .string(Self.day(firstDate)),
                "ends_before": hasEndDate ? .string(Self.day(secondDate)) : .null]
        case .ppe:
            return ["entity": .string("ppe"), "action": .string("handover"), "employee_id": employee,
                "item": .string(primary), "quantity": .number(number), "unit": .string(option),
                "handed_on": .string(Self.day(firstDate)), "signed_copy": .bool(false),
                "external_ref": .string(secondary)]
        case .equipment:
            return ["action": .string("register"), "workplace_id": place,
                "equipment_type": .string(Self.slug(primary)), "equipment_type_label": .string(primary),
                "serial_tag": .string(secondary.isEmpty ? UUID().uuidString.prefix(8).lowercased() : secondary),
                "acquired_on": .string(Self.day(firstDate)), "location_note": .string(notes)]
        case .katip:
            return ["kind": .string("katip_contract"), "action": .string("create"), "workplace_id": place,
                "counterparty": .string(primary), "expert_contact": .string(secondary), "scope": .string(notes),
                "starts_on": .string(Self.day(firstDate)), "ends_before": .string(Self.day(secondDate)),
                "declared_monthly_minutes": .number(number), "declared_note": .string(""),
                "contract_location": .string(""),
                "workspace_asset_id": assetID.map(IsgWorkspaceRPCValue.id) ?? .null]
        case .annualPlan:
            return ["kind": .string("annual_plan"), "action": .string("create"), "workplace_id": place,
                "plan_year": .number(Calendar.current.component(.year, from: firstDate))]
        case .board:
            return ["kind": .string("board"), "action": .string("create"), "workplace_id": place,
                "applicability": .string("mandatory"), "planned_on": .string(Self.day(firstDate)),
                "agenda": .array(lineValues(primary).map(IsgWorkspaceRPCValue.string))]
        case .workPermit:
            return ["kind": .string("work_permit"), "action": .string("create"), "workplace_id": place,
                "template_code": .string("general"), "job_description": .string(primary),
                "parties": .array([.string(secondary.isEmpty ? primary : secondary)]),
                "planned_on": .string(Self.day(firstDate)), "work_location": .string(secondary),
                "starts_at": .string(Self.instant(firstDate)), "ends_at": .string(Self.instant(secondDate)),
                "risk_precautions": .string(notes),
                "workspace_asset_id": assetID.map(IsgWorkspaceRPCValue.id) ?? .null]
        case .visit:
            return ["kind": .string("site_visit"), "action": .string("create"), "workplace_id": place,
                "visited_on": .string(Self.day(firstDate)), "location_note": .string(secondary),
                "expert_note": .string(primary), "responsible_contact": .string(notes)]
        case .personnel, .files: return [:]
        }
    }

    private var primaryLabel: String {
        switch domain {
        case .training: return label("localizable.nova.workspace.form.training.title", "Eğitim başlığı")
        case .risk: return label("localizable.nova.workspace.form.scope", "Kapsam özeti")
        case .nonconformity: return label("localizable.nova.workspace.form.finding.title", "Uygunsuzluk başlığı")
        case .checklist: return label("localizable.nova.workspace.form.template", "Şablon kodu")
        case .emergencyPlan: return label("localizable.nova.workspace.form.scope", "Kapsam özeti")
        case .ppe: return label("localizable.nova.workspace.form.ppe.item", "KKD ürünü")
        case .equipment: return label("localizable.nova.workspace.form.equipment.type", "Ekipman türü")
        case .katip: return label("localizable.nova.workspace.form.counterparty", "Sözleşme tarafı")
        case .board: return label("localizable.nova.workspace.form.agenda", "Gündem")
        case .workPermit: return label("localizable.nova.workspace.form.job", "İş tanımı")
        case .visit: return label("localizable.nova.workspace.form.expert.note", "Uzman notu")
        default: return domain.title
        }
    }
    private var secondaryLabel: String {
        switch domain {
        case .training: return label("localizable.nova.workspace.form.trainer", "Eğitmen")
        case .ppe: return label("localizable.nova.workspace.form.reference", "Referans")
        case .equipment: return label("localizable.nova.workspace.form.serial", "Seri / kod")
        case .katip: return label("localizable.nova.workspace.form.expert", "Uzman / iletişim")
        case .workPermit: return label("localizable.nova.workspace.form.location", "Çalışma yeri / taraf")
        case .visit: return label("localizable.nova.workspace.form.location", "Konum")
        default: return label("localizable.nova.workspace.form.detail", "Detay")
        }
    }
    private var attachmentCategory: String {
        switch domain {
        case .training: return "training_material"
        case .risk: return "risk_assessment"
        case .emergencyPlan, .drill: return "emergency_plan"
        case .ppe: return "handover_form"
        case .equipment: return "inspection_report"
        case .katip: return "contract"
        case .board: return "board_document"
        case .workPermit: return "permit_form"
        case .visit: return "visit_evidence"
        default: return "other"
        }
    }
    private var attachmentParentKind: String? {
        switch domain {
        case .training: return "training"
        case .risk: return "risk_assessment"
        case .nonconformity: return "nonconformity"
        case .checklist: return "checklist"
        case .emergencyPlan: return "emergency_plan"
        case .drill: return "drill"
        case .appointment: return "appointment"
        case .ppe: return "ppe"
        case .equipment: return "equipment"
        case .katip: return "katip_contract"
        case .annualPlan: return "annual_plan"
        case .board: return "board"
        case .workPermit: return "work_permit"
        case .visit: return "site_visit"
        case .personnel, .files: return nil
        }
    }
    private var attachmentFieldName: String {
        switch domain {
        case .risk: return "assessment"
        case .ppe: return "handover_form"
        case .board: return "minutes"
        case .workPermit: return "permit_form"
        case .visit: return "evidence"
        default: return "attachment"
        }
    }
    private var notesLabel: String { domain == .katip ? label("localizable.nova.workspace.form.scope", "Hizmet kapsamı") : label("localizable.nova.workspace.form.note", "Not") }
    private var optionLabel: String { label("localizable.nova.workspace.form.type", "Tür / durum") }
    private var numberLabel: String { domain == .training ? label("localizable.nova.workspace.form.minutes", "Süre (dakika)") : domain == .katip ? label("localizable.nova.workspace.form.monthly.minutes", "Aylık dakika") : label("localizable.nova.workspace.form.quantity", "Adet") }
    private var firstDateLabel: String { label("localizable.nova.workspace.form.start.date", "Başlangıç / kayıt tarihi") }
    private var secondDateLabel: String { label("localizable.nova.workspace.form.end.date", "Bitiş / termin tarihi") }
    private var defaultOption: String {
        switch domain { case .training: return "face_to_face"; case .nonconformity: return "medium"; case .appointment: return "representative"; case .ppe: return "piece"; case .board: return "mandatory"; default: return "" }
    }
    private var selectedRiskAssessment: IsgWorkspaceDomainRecord? {
        guard domain == .risk, let workplaceID else { return nil }
        return riskAssessments.first { fact("workplace_id", in: $0)?.lowercased() == workplaceID.uuidString.lowercased() }
    }
    private var selectedChecklistTemplate: IsgWorkspaceChecklistTemplate? {
        guard domain == .checklist, let checklistTemplateID else { return nil }
        return checklistTemplates.first { $0.id == checklistTemplateID }
    }
    private func fact(_ key: String, in row: IsgWorkspaceDomainRecord) -> String? {
        row.facts.first(where: { $0.0 == key })?.1
    }
    private var saveTitle: String {
        switch domain {
        case .training: return "Eğitimi kaydet"
        case .risk: return "Taslağı kaydet"
        case .nonconformity: return "Uygunsuzluğu kaydet"
        case .checklist: return "Kontrol listesini başlat"
        case .emergencyPlan: return "Planı kaydet"
        case .drill: return "Tatbikatı planla"
        case .appointment: return "Atamayı kaydet"
        case .ppe: return "Teslimi kaydet"
        case .equipment: return "Ekipmanı kaydet"
        case .katip: return "Sözleşmeyi kaydet"
        case .board: return "Toplantıyı kaydet"
        default: return "Kaydı oluştur"
        }
    }
    private func optionTitle(_ value: String) -> String { IsgWorkspaceDisplayText.value(value) }
    private func label(_ key: String, _ fallback: String) -> String { RDLocalization.string(key, table: .localizable, fallback: fallback) }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    private static func instant(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func startOfDayInstant(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: date))
    }
    private func lineValues(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    private static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
        let value = folded.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return value.count >= 3 ? String(value.prefix(40)) : "equipment"
    }
}
