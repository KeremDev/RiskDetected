import SwiftUI

/// Compact create surface for the primary D2-D6 records. Every command is
/// scoped by `IsgWorkspaceStore`; this view never calls a personal service.
struct IsgWorkspaceDomainCreateEditor: View {
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    let onDone: () -> Void
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var plans: [IsgWorkspaceDomainRecord] = []
    @State private var riskAssessments: [IsgWorkspaceDomainRecord] = []
    @State private var workplaceID: UUID?
    @State private var employeeID: UUID?
    @State private var planID: UUID?
    @State private var primary = ""
    @State private var secondary = ""
    @State private var notes = ""
    @State private var option = ""
    @State private var number = 1
    @State private var firstDate = Date()
    @State private var secondDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
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
                        RDLocalization.string("localizable.nova.editor.kaydet.8f6f32fd", table: .localizable, fallback: "Kaydet"),
                        symbol: "checkmark", prominent: true, enabled: canSave && !saving) { save() }
                }
            }.padding(18).novaPopupContentSize()
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await prepare() }
    }

    @ViewBuilder private var form: some View {
        if needsWorkplace { workplacePicker }
        if needsEmployee { employeePicker }
        if domain == .drill { planPicker }
        switch domain {
        case .training:
            textField(primaryLabel, text: $primary)
            textField(secondaryLabel, text: $secondary)
            optionPicker(label: optionLabel, values: ["face_to_face", "online", "mixed"])
            datePicker(firstDateLabel, selection: $firstDate, components: [.date, .hourAndMinute])
            numberField(numberLabel)
            textField(notesLabel, text: $notes)
        case .risk, .nonconformity:
            textField(primaryLabel, text: $primary)
            if domain == .nonconformity {
                optionPicker(label: optionLabel, values: ["low", "medium", "high", "critical"])
                datePicker(firstDateLabel, selection: $firstDate)
                datePicker(secondDateLabel, selection: $secondDate)
            } else {
                datePicker(firstDateLabel, selection: $firstDate)
                if selectedRiskAssessment != nil {
                    textField(label("localizable.nova.workspace.form.revision.reason", "Revizyon nedeni"), text: $notes)
                    NovaHelpHint(text: label("localizable.nova.workspace.form.revision.hint",
                        "Bu işyerinde mevcut değerlendirme bulunduğu için yeni sürüm oluşturulur."))
                }
            }
        case .checklist:
            textField(primaryLabel, text: $primary)
            numberField(numberLabel)
            datePicker(firstDateLabel, selection: $firstDate)
        case .emergencyPlan:
            textField(primaryLabel, text: $primary)
            datePicker(firstDateLabel, selection: $firstDate)
            datePicker(secondDateLabel, selection: $secondDate)
            textField(notesLabel, text: $notes)
        case .drill:
            datePicker(firstDateLabel, selection: $firstDate)
        case .appointment:
            optionPicker(label: optionLabel, values: ["representative", "support_staff", "team_member", "first_aid", "fire_team"])
            datePicker(firstDateLabel, selection: $firstDate)
            datePicker(secondDateLabel, selection: $secondDate)
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
            textField(primaryLabel, text: $primary)
            optionPicker(label: optionLabel, values: ["mandatory", "voluntary"])
            datePicker(firstDateLabel, selection: $firstDate)
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
        [.emergencyPlan, .appointment, .ppe].contains(domain)
    }
    private var canSave: Bool {
        if needsWorkplace && workplaceID == nil { return false }
        if needsEmployee && employeeID == nil { return false }
        if domain == .drill && planID == nil { return false }
        switch domain {
        case .training, .nonconformity, .emergencyPlan, .ppe, .equipment, .board, .workPermit, .visit:
            return !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .risk:
            return !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (selectedRiskAssessment == nil || notes.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10)
        case .katip: return !primary.isEmpty && !secondary.isEmpty && !notes.isEmpty
        case .checklist: return !primary.isEmpty
        case .personnel, .files: return false
        default: return true
        }
    }

    @MainActor private func prepare() async {
        loading = true; error = nil
        do {
            if needsWorkplace { workplaces = try await store.directory(.workplace); workplaceID = workplaces.first?.id }
            if needsEmployee { employees = try await store.employees(); employeeID = employees.first?.id }
            if domain == .drill { plans = try await store.domain(.emergencyPlan).rows; planID = plans.first?.id }
            if domain == .risk { riskAssessments = try await store.domain(.risk).rows }
            option = defaultOption
            number = domain == .training ? 60 : 1
        } catch {
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                                               fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        loading = false
    }

    private func save() {
        guard canSave else { return }
        saving = true; error = nil
        Task { @MainActor in
            do {
                _ = try await store.mutateDomain(mutationID: UUID(), domain: domain, payload: payload())
                celebrate(NovaSuccessMessage.recordSaved(domain.title))
                onDone()
            } catch {
                self.error = RDLocalization.string("localizable.nova.workspace.mutation.failed", table: .localizable,
                    fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
            }
            saving = false
        }
    }

    private func payload() -> [String: IsgWorkspaceRPCValue] {
        let place = IsgWorkspaceRPCValue.id(workplaceID)
        let employee = IsgWorkspaceRPCValue.id(employeeID)
        switch domain {
        case .training:
            var participants: [IsgWorkspaceRPCValue] = []
            if let employeeID { participants = [.object(["id": .id(employeeID), "attended": .bool(firstDate <= Date())])] }
            return ["action": .string("save"), "expected_version": .number(0), "title": .string(primary),
                "trainer": .string(secondary.isEmpty ? primary : secondary), "method": .string(option),
                "starts_at": .string(Self.instant(firstDate)), "duration_minutes": .number(number),
                "valid_until": .null, "location": .string(""), "notes": .string(notes),
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
            return ["action": .string("create"), "workplace_id": place, "template_code": .string(primary),
                "template_version": .number(number), "started_on": .string(Self.day(firstDate))]
        case .emergencyPlan:
            return ["entity": .string("plan"), "action": .string("publish"), "workplace_id": place,
                "scope": .string(primary), "prepared_on": .string(Self.day(firstDate)),
                "valid_until": .string(Self.day(secondDate)), "review_note": .string(notes),
                "team": .array([.object(["employee_id": employee, "role": .string("coordinator"), "contact": .string("")])])]
        case .drill:
            let version = plans.first(where: { $0.id == planID })?.version ?? 1
            return ["entity": .string("drill"), "action": .string("create"), "workplace_id": place,
                "plan_id": .id(planID), "plan_version": .number(Int(version)), "planned_on": .string(Self.day(firstDate))]
        case .appointment:
            return ["entity": .string("appointment"), "action": .string("create"), "employee_id": employee,
                "workplace_id": place, "kind": .string(option), "starts_on": .string(Self.day(firstDate)),
                "ends_before": .string(Self.day(secondDate))]
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
                "declared_monthly_minutes": .number(number), "declared_note": .string(""), "contract_location": .string("")]
        case .annualPlan:
            return ["kind": .string("annual_plan"), "action": .string("create"), "workplace_id": place,
                "plan_year": .number(Calendar.current.component(.year, from: firstDate))]
        case .board:
            return ["kind": .string("board"), "action": .string("create"), "workplace_id": place,
                "applicability": .string(option), "planned_on": .string(Self.day(firstDate)),
                "agenda": .array([.string(primary)])]
        case .workPermit:
            return ["kind": .string("work_permit"), "action": .string("create"), "workplace_id": place,
                "template_code": .string("general"), "job_description": .string(primary),
                "parties": .array([.string(secondary.isEmpty ? primary : secondary)]),
                "planned_on": .string(Self.day(firstDate)), "work_location": .string(secondary),
                "starts_at": .string(Self.instant(firstDate)), "ends_at": .string(Self.instant(secondDate)),
                "risk_precautions": .string(notes), "workspace_asset_id": .null]
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
    private var notesLabel: String { domain == .katip ? label("localizable.nova.workspace.form.scope", "Hizmet kapsamı") : label("localizable.nova.workspace.form.note", "Not") }
    private var optionLabel: String { label("localizable.nova.workspace.form.type", "Tür / durum") }
    private var numberLabel: String { domain == .training ? label("localizable.nova.workspace.form.minutes", "Süre (dakika)") : domain == .katip ? label("localizable.nova.workspace.form.monthly.minutes", "Aylık dakika") : label("localizable.nova.workspace.form.quantity", "Adet") }
    private var firstDateLabel: String { label("localizable.nova.workspace.form.start.date", "Başlangıç / kayıt tarihi") }
    private var secondDateLabel: String { label("localizable.nova.workspace.form.end.date", "Bitiş / termin tarihi") }
    private var defaultOption: String {
        switch domain { case .training: return "face_to_face"; case .nonconformity: return "medium"; case .appointment: return "representative"; case .ppe: return "piece"; case .board: return "voluntary"; default: return "" }
    }
    private var selectedRiskAssessment: IsgWorkspaceDomainRecord? {
        guard domain == .risk, let workplaceID else { return nil }
        return riskAssessments.first { fact("workplace_id", in: $0)?.lowercased() == workplaceID.uuidString.lowercased() }
    }
    private func fact(_ key: String, in row: IsgWorkspaceDomainRecord) -> String? {
        row.facts.first(where: { $0.0 == key })?.1
    }
    private func optionTitle(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
    private func label(_ key: String, _ fallback: String) -> String { RDLocalization.string(key, table: .localizable, fallback: fallback) }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    private static func instant(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
        let value = folded.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return value.count >= 3 ? String(value.prefix(40)) : "equipment"
    }
}
