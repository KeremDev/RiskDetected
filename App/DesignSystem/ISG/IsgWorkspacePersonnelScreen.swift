import SwiftUI

enum IsgPersonnelSection: String, CaseIterable, Identifiable {
    case employee, workplace, department, jobRole, contractor, engagement, assignment
    var id: String { rawValue }
    var title: String {
        switch self {
        case .employee: return RDLocalization.string("localizable.nova.workspace.personnel.employees", table: .localizable, fallback: "Personeller")
        case .workplace: return RDLocalization.string("localizable.nova.workspace.personnel.workplaces", table: .localizable, fallback: "İşyerleri")
        case .department: return RDLocalization.string("localizable.nova.workspace.personnel.departments", table: .localizable, fallback: "Departmanlar")
        case .jobRole: return RDLocalization.string("localizable.isg.workspace.personnel.screen.gorevler.8c6c8384", table: .localizable, fallback: "Görevler")
        case .contractor: return RDLocalization.string("localizable.isg.workspace.personnel.screen.dis.firmalar.98d3dbdb", table: .localizable, fallback: "Dış firmalar")
        case .engagement: return RDLocalization.string("localizable.isg.workspace.personnel.screen.sozlesmeler.45c00a90", table: .localizable, fallback: "Sözleşmeler")
        case .assignment: return RDLocalization.string("localizable.isg.workspace.personnel.screen.atama.gecmisi.48189d0d", table: .localizable, fallback: "Atama geçmişi")
        }
    }
}

private struct IsgDirectoryRoute: Identifiable {
    let id = UUID()
    let kind: IsgWorkspaceDirectoryKind
    let entry: IsgWorkspaceDirectoryEntry?
}

private struct IsgEmployeeRoute: Identifiable {
    let id = UUID()
    let entry: IsgWorkspaceEmployeeEntry?
}

private struct IsgPersonnelAdvancedRoute: Identifiable {
    let id = UUID()
    let section: IsgPersonnelSection
    let entry: IsgWorkspaceAdvancedRecord?
}

struct IsgWorkspacePersonnelScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let companyName: String
    let canOperate: Bool
    let canManageDirectory: Bool
    let onBack: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section: IsgPersonnelSection
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var departments: [IsgWorkspaceDirectoryEntry] = []
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var jobRoles: [IsgWorkspaceAdvancedRecord] = []
    @State private var contractors: [IsgWorkspaceAdvancedRecord] = []
    @State private var engagements: [IsgWorkspaceAdvancedRecord] = []
    @State private var assignments: [IsgWorkspaceAdvancedRecord] = []
    @State private var metrics: IsgPersonnelMetrics?
    @State private var directoryRoute: IsgDirectoryRoute?
    @State private var employeeRoute: IsgEmployeeRoute?
    @State private var advancedRoute: IsgPersonnelAdvancedRoute?
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()

    init(store: IsgWorkspaceStore, companyName: String, canOperate: Bool,
         canManageDirectory: Bool, initialSection: IsgPersonnelSection = .employee,
         onBack: @escaping () -> Void) {
        self.store = store
        self.companyName = companyName
        self.canOperate = canOperate
        self.canManageDirectory = canManageDirectory
        self.onBack = onBack
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    NovaListHeading(title: IsgWorkspaceDomain.personnel.title, onBack: onBack, actionBelow: true) {
                        if canAdd {
                            NovaListActionButton(title: addTitle, symbol: "plus", tone: .primary,
                                identifier: "osgb.personnel.add") { openCreate() }
                        }
                    }
                    NovaListHint(text: String(format: RDLocalization.string(
                        "localizable.nova.workspace.domain.scope", table: .localizable,
                        fallback: "%@ firmasına ait yetkili OSGB kayıtları gösteriliyor."), companyName))
                    if let metrics {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                 count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                            NovaListStat(title: IsgPersonnelSection.employee.title, symbol: "person.2",
                                         value: String(metrics.employees.active))
                            NovaListStat(title: IsgPersonnelSection.workplace.title, symbol: "building.2",
                                         value: String(metrics.workplaces.active))
                            NovaListStat(title: IsgPersonnelSection.department.title, symbol: "square.grid.2x2",
                                         value: String(metrics.departments.active))
                            NovaListStat(title: IsgPersonnelSection.jobRole.title, symbol: "briefcase",
                                         value: String(metrics.jobRoles.active))
                            NovaListStat(title: IsgPersonnelSection.contractor.title, symbol: "building.2.crop.circle",
                                         value: String(metrics.contractors.active))
                            NovaListStat(title: IsgPersonnelSection.assignment.title, symbol: "arrow.triangle.branch",
                                         value: String(metrics.assignments.current))
                        }
                    }
                    searchField
                    sectionPicker
                    NovaListSectionHeading(title: section.title, count: "\(visibleCount) kayıt")
                    if loading {
                        NovaLoadingView(message: RDLocalization.string("localizable.nova.workspace.domain.loading",
                            table: .localizable, fallback: "Kayıtlar yükleniyor…"))
                    } else if let error {
                        NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.domain.failed",
                            table: .localizable, fallback: "Kayıtlar yüklenemedi"), message: error)
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.domain.retry",
                            table: .localizable, fallback: "Tekrar dene"), symbol: "arrow.clockwise") { revision = UUID() }
                    } else if visibleCount == 0 {
                        NovaEmptyState(title: String(format: RDLocalization.string(
                            "localizable.nova.workspace.domain.empty", table: .localizable,
                            fallback: "Henüz %@ kaydı yok."), section.title),
                            message: RDLocalization.string("localizable.nova.workspace.personnel.empty.detail",
                                table: .localizable, fallback: "Firma personel dizinini başlatmak için işyeri, departman veya personel ekleyin."))
                    } else { records }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
                    .novaAsyncContent(isLoading: loading)
                    .novaListEntrance(hasRecords: visibleCount > 0)
            }.refreshable { revision = UUID() }
        }
        .task(id: revision) { await load() }
        .novaPopup(item: $directoryRoute, onDismiss: { revision = UUID() }) { route in
            IsgWorkspaceDirectoryEditor(store: store, route: route, workplaces: workplaces) { directoryRoute = nil }
        }
        .novaPopup(item: $employeeRoute, onDismiss: { revision = UUID() }) { route in
            IsgWorkspaceEmployeeEditor(store: store, route: route, departments: departments) { employeeRoute = nil }
        }
        .novaPopup(item: $advancedRoute, onDismiss: { revision = UUID() }) { route in
            IsgWorkspacePersonnelAdvancedEditor(store: store, route: route, workplaces: workplaces,
                departments: departments, employees: employees, jobRoles: jobRoles,
                contractors: contractors, engagements: engagements) { advancedRoute = nil }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IsgPersonnelSection.allCases) { item in
                    Button { section = item } label: {
                        Text(item.title).font(NovaFont.font(.meta))
                            .foregroundStyle(section == item ? Color.white : Color.primary)
                            .padding(.horizontal, 12).frame(minHeight: 38)
                            .background(section == item ? Color.black : Color.white.opacity(0.72), in: Capsule())
                    }.buttonStyle(NovaRowPressStyle())
                }
            }
        }
    }

    private var searchField: some View {
        NovaAnalysisSearchField(text: $query,
            placeholder: RDLocalization.string("localizable.nova.workspace.domain.search", table: .localizable,
                fallback: "Kayıtlarda ara"), identifier: "osgb.personnel.search")
    }

    @ViewBuilder private var records: some View {
        switch section {
        case .employee:
            ForEach(Array(employees.filter { matches($0.code, $0.name) }.enumerated()), id: \.element.id) { index, row in
                rowButton(title: row.name, subtitle: row.code, symbol: "person") {
                    employeeRoute = .init(entry: row)
                }.novaRowEntrance(index)
            }
        case .workplace:
            ForEach(Array(workplaces.filter { matches($0.code, $0.name) }.enumerated()), id: \.element.id) { index, row in
                rowButton(title: row.name, subtitle: row.code, symbol: "building.2") {
                    directoryRoute = .init(kind: .workplace, entry: row)
                }.novaRowEntrance(index)
            }
        case .department:
            ForEach(Array(departments.filter { matches($0.code, $0.name) }.enumerated()), id: \.element.id) { index, row in
                rowButton(title: row.name, subtitle: row.code, symbol: "square.grid.2x2") {
                    directoryRoute = .init(kind: .department, entry: row)
                }.novaRowEntrance(index)
            }
        case .jobRole:
            advancedRows(jobRoles, symbol: "briefcase")
        case .contractor:
            advancedRows(contractors, symbol: "building.2.crop.circle")
        case .engagement:
            advancedRows(engagements, symbol: "doc.text")
        case .assignment:
            advancedRows(assignments, symbol: "arrow.triangle.branch")
        }
    }

    @ViewBuilder private func advancedRows(_ values: [IsgWorkspaceAdvancedRecord], symbol: String) -> some View {
        ForEach(Array(values.filter { matches($0.title, $0.subtitle ?? "", $0.status ?? "") }.enumerated()),
                id: \.element.id) { index, row in
            rowButton(title: row.title,
                      subtitle: [row.subtitle, row.status.map(IsgWorkspaceDisplayText.value)]
                        .compactMap { $0 }.joined(separator: " · "),
                      symbol: symbol) { advancedRoute = .init(section: section, entry: row) }
                .novaRowEntrance(index)
        }
    }

    private func rowButton(title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaCard(padding: 14) {
                HStack(spacing: 10) {
                    NovaIcon(symbol: symbol, size: 19)
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: title, style: .bodyStrong)
                        NovaText(text: subtitle, style: .metaQuiet)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.contentShape(Rectangle())
            }
        }.buttonStyle(NovaRowPressStyle())
    }

    private var visibleCount: Int {
        switch section {
        case .employee: return employees.filter { matches($0.code, $0.name) }.count
        case .workplace: return workplaces.filter { matches($0.code, $0.name) }.count
        case .department: return departments.filter { matches($0.code, $0.name) }.count
        case .jobRole: return jobRoles.filter { matches($0.title, $0.subtitle ?? "") }.count
        case .contractor: return contractors.filter { matches($0.title, $0.subtitle ?? "") }.count
        case .engagement: return engagements.filter { matches($0.title, $0.subtitle ?? "") }.count
        case .assignment: return assignments.filter { matches($0.title, $0.subtitle ?? "") }.count
        }
    }
    private var canAdd: Bool {
        switch section {
        case .employee, .assignment: return canOperate
        default: return canManageDirectory
        }
    }
    private var addTitle: String { String(format: RDLocalization.string(
        "localizable.nova.workspace.personnel.add", table: .localizable, fallback: "Kayıt ekle"), section.title) }
    private func matches(_ values: String...) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
    private func openCreate() {
        switch section {
        case .employee: employeeRoute = .init(entry: nil)
        case .workplace: directoryRoute = .init(kind: .workplace, entry: nil)
        case .department: directoryRoute = .init(kind: .department, entry: nil)
        case .jobRole, .contractor, .engagement, .assignment:
            advancedRoute = .init(section: section, entry: nil)
        }
    }
    @MainActor private func load() async {
        loading = true; error = nil
        do {
            async let workplaceRows = store.directory(.workplace)
            async let departmentRows = store.directory(.department)
            async let employeeRows = store.employees()
            async let metricRows = store.personnelMetrics()
            async let roleRows = store.personnelAdvanced(.jobRoles)
            async let contractorRows = store.personnelAdvanced(.contractors)
            async let engagementRows = store.personnelAdvanced(.engagements)
            async let assignmentRows = store.personnelAdvanced(.assignments)
            (workplaces, departments, employees, metrics, jobRoles, contractors, engagements, assignments) = try await
                (workplaceRows, departmentRows, employeeRows, metricRows, roleRows, contractorRows,
                 engagementRows, assignmentRows)
        } catch {
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry",
                table: .localizable, fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        loading = false
    }
}

private struct IsgWorkspaceDirectoryEditor: View {
    @ObservedObject var store: IsgWorkspaceStore
    let route: IsgDirectoryRoute
    let workplaces: [IsgWorkspaceDirectoryEntry]
    let onDone: () -> Void
    @State private var code: String
    @State private var name: String
    @State private var workplaceID: UUID?
    @State private var working = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    init(store: IsgWorkspaceStore, route: IsgDirectoryRoute, workplaces: [IsgWorkspaceDirectoryEntry], onDone: @escaping () -> Void) {
        self.store = store; self.route = route; self.workplaces = workplaces; self.onDone = onDone
        _code = State(initialValue: route.entry?.code ?? "")
        _name = State(initialValue: route.entry?.name ?? "")
        _workplaceID = State(initialValue: route.entry?.workplaceID ?? workplaces.first?.id)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: route.entry == nil ? addTitle : editTitle,
                                 symbol: route.kind == .workplace ? "building.2" : "square.grid.2x2")
                field(label: RDLocalization.string("localizable.nova.workspace.personnel.code", table: .localizable, fallback: "Kod"), text: $code)
                field(label: RDLocalization.string("localizable.nova.workspace.personnel.name", table: .localizable, fallback: "Ad"), text: $name)
                if route.kind == .department && !workplaces.isEmpty {
                    Picker(IsgPersonnelSection.workplace.title, selection: $workplaceID) {
                        ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                }
                if let error { NovaHelpHint(text: error) }
                NovaCompactActionButton(title: saveTitle, symbol: "checkmark", prominent: true,
                    enabled: !working && !code.trimmingCharacters(in: .whitespaces).isEmpty &&
                        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
                        (route.kind == .workplace || workplaces.isEmpty || workplaceID != nil)) { save() }
                if route.entry != nil {
                    NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.personnel.archive",
                        table: .localizable, fallback: "Arşivle"), symbol: "archivebox", enabled: !working) { archive() }
                }
            }.padding(18).novaPopupContentSize()
        }
    }
    private func field(label: String, text: Binding<String>) -> some View {
        TextField(label, text: text).font(NovaFont.font(.body)).padding(14).novaControlBackground(cornerRadius: 14)
    }
    private var addTitle: String { String(format: RDLocalization.string("localizable.nova.workspace.personnel.add",
        table: .localizable, fallback: "Kayıt ekle"), route.kind == .workplace ? IsgPersonnelSection.workplace.title : IsgPersonnelSection.department.title) }
    private var editTitle: String { RDLocalization.string("localizable.nova.workspace.personnel.edit", table: .localizable, fallback: "Düzenle") }
    private var saveTitle: String { working ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…") : RDLocalization.string("localizable.nova.editor.kaydet.8f6f32fd", table: .localizable, fallback: "Kaydet") }
    private func save() { mutate(route.entry == nil ? "create" : "edit") }
    private func archive() { mutate("archive") }
    private func mutate(_ action: String) {
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "directory.\(route.kind.rawValue).\(action)", components: [
            route.entry?.id.uuidString ?? "", String(route.entry?.version ?? 0),
            workplaceID?.uuidString ?? "", code, name
        ])
        mutationAttempt = attempt
        working = true; error = nil
        Task { @MainActor in
            do {
                try await store.mutateDirectory(mutationID: mutationID, kind: route.kind, action: action,
                    entryID: route.entry?.id, expectedVersion: route.entry?.version ?? 0,
                    workplaceID: route.kind == .department ? workplaceID : nil, code: code, name: name)
                celebrate(NovaSuccessMessage.recordSaved(route.kind == .workplace ? IsgPersonnelSection.workplace.title : IsgPersonnelSection.department.title))
                onDone()
            } catch { self.error = RDLocalization.string("localizable.nova.workspace.mutation.failed", table: .localizable, fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.") }
            working = false
        }
    }
}

private struct IsgWorkspaceEmployeeEditor: View {
    @ObservedObject var store: IsgWorkspaceStore
    let route: IsgEmployeeRoute
    let departments: [IsgWorkspaceDirectoryEntry]
    let onDone: () -> Void
    @State private var code: String
    @State private var name: String
    @State private var departmentID: UUID?
    @State private var hiredOn = Date()
    @State private var hasEnd = false
    @State private var endsBefore = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var working = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    init(store: IsgWorkspaceStore, route: IsgEmployeeRoute, departments: [IsgWorkspaceDirectoryEntry], onDone: @escaping () -> Void) {
        self.store = store; self.route = route; self.departments = departments; self.onDone = onDone
        _code = State(initialValue: route.entry?.code ?? "")
        _name = State(initialValue: route.entry?.name ?? "")
        _departmentID = State(initialValue: route.entry?.departmentID ?? departments.first?.id)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: route.entry == nil ? RDLocalization.string("localizable.nova.workspace.personnel.employee.add", table: .localizable, fallback: "Personel ekle") : RDLocalization.string("localizable.nova.workspace.personnel.employee.edit", table: .localizable, fallback: "Personeli düzenle"), symbol: "person")
                TextField(RDLocalization.string("localizable.nova.workspace.personnel.code", table: .localizable, fallback: "Kod"), text: $code).padding(14).novaControlBackground(cornerRadius: 14)
                TextField(RDLocalization.string("localizable.nova.workspace.personnel.fullname", table: .localizable, fallback: "Ad soyad"), text: $name).padding(14).novaControlBackground(cornerRadius: 14)
                if !departments.isEmpty {
                    Picker(IsgPersonnelSection.department.title, selection: $departmentID) {
                        Text(RDLocalization.string("localizable.nova.workspace.personnel.department.none", table: .localizable, fallback: "Departman yok")).tag(UUID?.none)
                        ForEach(departments) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                }
                DatePicker(RDLocalization.string("localizable.nova.workspace.personnel.hired", table: .localizable, fallback: "İşe giriş tarihi"), selection: $hiredOn, displayedComponents: .date).padding(12).novaControlBackground(cornerRadius: 14)
                Toggle(RDLocalization.string("localizable.nova.workspace.personnel.has.end", table: .localizable, fallback: "Bitiş tarihi var"), isOn: $hasEnd).padding(12).novaControlBackground(cornerRadius: 14)
                if hasEnd { DatePicker(RDLocalization.string("localizable.nova.workspace.personnel.ends", table: .localizable, fallback: "Bitiş tarihi"), selection: $endsBefore, in: hiredOn..., displayedComponents: .date).padding(12).novaControlBackground(cornerRadius: 14) }
                IsgWorkspaceInlineAttachmentField(
                    title: RDLocalization.string("localizable.isg.workspace.personnel.screen.personel.belgesi.ekle.istege.bagli.e4a94473", table: .localizable, fallback: "Personel belgesi ekle (isteğe bağlı)"),
                    attachment: $attachment)
                if let error { NovaHelpHint(text: error) }
                NovaCompactActionButton(title: working ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…") : RDLocalization.string("localizable.nova.editor.kaydet.8f6f32fd", table: .localizable, fallback: "Kaydet"), symbol: "checkmark", prominent: true, enabled: !working && !code.isEmpty && !name.isEmpty) { mutate(route.entry == nil ? "create" : "edit") }
                if route.entry != nil { NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.personnel.archive", table: .localizable, fallback: "Arşivle"), symbol: "archivebox", enabled: !working) { mutate("archive") } }
            }.padding(18).novaPopupContentSize()
        }
    }
    private func mutate(_ action: String) {
        let hired = action == "archive" ? nil : Self.day(hiredOn)
        let ending = action == "archive" || !hasEnd ? nil : Self.day(endsBefore)
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "employee.\(action)", components: [
            route.entry?.id.uuidString ?? "", String(route.entry?.version ?? 0), code, name,
            departmentID?.uuidString ?? "", hired ?? "", ending ?? ""
        ])
        mutationAttempt = attempt
        working = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded(action: action)
                let employee = try await store.mutateEmployee(mutationID: mutationID, action: action, employeeID: route.entry?.id,
                    expectedVersion: route.entry?.version ?? 0, code: code, name: name, departmentID: departmentID,
                    hiredOn: hired, endsBefore: ending)
                if let uploaded, let employeeID = employee?.id ?? route.entry?.id {
                    var attachAttempt = mutationAttempt
                    let attachID = attachAttempt.id(namespace: "employee.file.attach", components: [
                        uploaded.entryID.uuidString, employeeID.uuidString
                    ])
                    mutationAttempt = attachAttempt
                    _ = try await store.attachFile(
                        mutationID: attachID, entryID: uploaded.entryID,
                        parentKind: "employee", parentID: employeeID,
                        fieldName: "personnel_document")
                }
                celebrate(action == "archive" ? NovaSuccessMessage.personnelArchived : (route.entry == nil ? NovaSuccessMessage.personnelCreated : NovaSuccessMessage.personnelUpdated))
                onDone()
            } catch { self.error = RDLocalization.string("localizable.nova.workspace.mutation.failed", table: .localizable, fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.") }
            working = false
        }
    }
    private func uploadAttachmentIfNeeded(action: String) async throws -> IsgWorkspaceFileUploadResult? {
        guard action != "archive", let attachment else { return nil }
        var uploadAttempt = mutationAttempt
        let uploadID = uploadAttempt.id(namespace: "employee.file.upload", components: [
            attachment.filename, IsgWorkspaceMutationAttempt.digest(attachment.data)
        ])
        mutationAttempt = uploadAttempt
        return try await store.uploadFile(
            mutationID: uploadID, title: attachment.title,
            filename: attachment.filename, category: "personnel_document",
            data: attachment.data)
    }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
}

private struct IsgWorkspacePersonnelAdvancedEditor: View {
    @ObservedObject var store: IsgWorkspaceStore
    let route: IsgPersonnelAdvancedRoute
    let workplaces: [IsgWorkspaceDirectoryEntry]
    let departments: [IsgWorkspaceDirectoryEntry]
    let employees: [IsgWorkspaceEmployeeEntry]
    let jobRoles: [IsgWorkspaceAdvancedRecord]
    let contractors: [IsgWorkspaceAdvancedRecord]
    let engagements: [IsgWorkspaceAdvancedRecord]
    let onDone: () -> Void
    @State private var code = ""
    @State private var name = ""
    @State private var details = ""
    @State private var relation = "contractor"
    @State private var taxIdentifier = ""
    @State private var contactName = ""
    @State private var contactValue = ""
    @State private var workplaceID: UUID?
    @State private var contractorID: UUID?
    @State private var employeeID: UUID?
    @State private var departmentID: UUID?
    @State private var jobRoleID: UUID?
    @State private var engagementID: UUID?
    @State private var startsOn = Date()
    @State private var endsOn = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var working = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    init(store: IsgWorkspaceStore, route: IsgPersonnelAdvancedRoute,
         workplaces: [IsgWorkspaceDirectoryEntry], departments: [IsgWorkspaceDirectoryEntry],
         employees: [IsgWorkspaceEmployeeEntry], jobRoles: [IsgWorkspaceAdvancedRecord],
         contractors: [IsgWorkspaceAdvancedRecord], engagements: [IsgWorkspaceAdvancedRecord],
         onDone: @escaping () -> Void) {
        self.store = store; self.route = route; self.workplaces = workplaces; self.departments = departments
        self.employees = employees; self.jobRoles = jobRoles; self.contractors = contractors
        self.engagements = engagements; self.onDone = onDone
        _code = State(initialValue: route.entry?.text("code") ?? "")
        _name = State(initialValue: route.entry?.text("name") ?? "")
        _details = State(initialValue: route.entry?.text("description") ?? route.entry?.text("scope") ?? "")
        _relation = State(initialValue: route.entry?.text("relation_kind") ?? "contractor")
        _taxIdentifier = State(initialValue: route.entry?.text("tax_identifier") ?? "")
        _contactName = State(initialValue: route.entry?.text("contact_name") ?? "")
        _contactValue = State(initialValue: route.entry?.text("contact_value") ?? "")
        _workplaceID = State(initialValue: route.entry?.uuid("workplace_id") ?? workplaces.first?.id)
        _contractorID = State(initialValue: route.entry?.uuid("contractor_id") ?? contractors.first?.id)
        _employeeID = State(initialValue: route.entry?.uuid("employee_id") ?? employees.first?.id)
        _departmentID = State(initialValue: route.entry?.uuid("department_id") ?? departments.first?.id)
        _jobRoleID = State(initialValue: route.entry?.uuid("job_role_id") ?? jobRoles.first?.id)
        _engagementID = State(initialValue: route.entry?.uuid("contractor_engagement_id"))
        let start = Self.date(route.entry?.text(route.section == .engagement ? "starts_on" : "effective_from")) ?? Date()
        _startsOn = State(initialValue: start)
        _endsOn = State(initialValue: Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: start) ?? start)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: route.entry == nil ? "\(route.section.title) ekle" : route.section.title,
                                 symbol: symbol, subtitle: RDLocalization.string("localizable.isg.workspace.personnel.screen.kayit.secili.firma.kapsaminda.tutulur.gecmis.sat.51db5224", table: .localizable, fallback: "Kayıt seçili firma kapsamında tutulur; geçmiş satırları korunur."))
                fields
                if let error { NovaHelpHint(text: error) }
                if route.entry == nil || [.jobRole, .contractor].contains(route.section) {
                    NovaCompactActionButton(title: working ? "Kaydediliyor…" : "Kaydet", symbol: "checkmark",
                                            prominent: true, enabled: canSave && !working) { save() }
                }
                if let entry = route.entry {
                    if [.jobRole, .contractor].contains(route.section) {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.isg.workspace.personnel.screen.arsivle.d0f5b9ce", table: .localizable, fallback: "Arşivle"), symbol: "archivebox", enabled: !working) {
                            mutate(action: route.section == .jobRole ? "job_role_archive" : "contractor_archive")
                        }
                    } else if entry.text(route.section == .engagement ? "state" : "effective_before") ==
                                (route.section == .engagement ? "active" : nil) {
                        DatePicker("Bitiş tarihi", selection: $endsOn, in: minimumEndDate..., displayedComponents: .date)
                            .padding(12).novaControlBackground(cornerRadius: 14)
                        NovaCompactActionButton(title: RDLocalization.string("localizable.isg.workspace.personnel.screen.kaydi.sonlandir.1b6c5a02", table: .localizable, fallback: "Kaydı sonlandır"), symbol: "calendar.badge.minus", enabled: !working) {
                            mutate(action: route.section == .engagement ? "engagement_end" : "assignment_end")
                        }
                    }
                }
            }.padding(18).novaPopupContentSize()
        }.scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var fields: some View {
        switch route.section {
        case .jobRole:
            field(RDLocalization.string("localizable.isg.workspace.personnel.screen.gorev.kodu.51b0a1e4", table: .localizable, fallback: "Görev kodu"), text: $code); field(RDLocalization.string("localizable.isg.workspace.personnel.screen.gorev.adi.f8a00811", table: .localizable, fallback: "Görev adı"), text: $name); field(RDLocalization.string("localizable.isg.workspace.personnel.screen.aciklama.73b8a51a", table: .localizable, fallback: "Açıklama"), text: $details)
        case .contractor:
            field(RDLocalization.string("localizable.isg.workspace.personnel.screen.firma.adi.0a2e3e00", table: .localizable, fallback: "Firma adı"), text: $name)
            picker("İlişki", selection: $relation, values: ["subcontractor", "contractor", "supplier", "other"])
            field(RDLocalization.string("localizable.isg.workspace.personnel.screen.vergi.kayit.no.be6090f5", table: .localizable, fallback: "Vergi / kayıt no"), text: $taxIdentifier); field(RDLocalization.string("localizable.isg.workspace.personnel.screen.iletisim.kisisi.174025ee", table: .localizable, fallback: "İletişim kişisi"), text: $contactName)
            field(RDLocalization.string("localizable.isg.workspace.personnel.screen.telefon.veya.e.posta.80c4de49", table: .localizable, fallback: "Telefon veya e-posta"), text: $contactValue)
        case .engagement where route.entry == nil:
            picker("Dış firma", selection: $contractorID, values: contractors)
            if !workplaces.isEmpty { picker("İşyeri", selection: $workplaceID, values: workplaces) }
            field(RDLocalization.string("localizable.isg.workspace.personnel.screen.isin.kapsami.da152f1f", table: .localizable, fallback: "İşin kapsamı"), text: $details)
            DatePicker("Başlangıç", selection: $startsOn, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
        case .assignment where route.entry == nil:
            picker("Personel", selection: $employeeID, values: employees)
            picker("Departman", selection: $departmentID, values: departments, optional: true)
            picker("Görev", selection: $jobRoleID, values: jobRoles, optional: true)
            picker("Dış firma sözleşmesi", selection: $engagementID, values: engagements.filter { $0.status == "active" }, optional: true)
            DatePicker("Başlangıç", selection: $startsOn, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
        default:
            EmptyView()
        }
    }

    private var symbol: String {
        switch route.section { case .jobRole: return "briefcase"; case .contractor: return "building.2.crop.circle"
        case .engagement: return "doc.text"; default: return "arrow.triangle.branch" }
    }
    private var canSave: Bool {
        switch route.section {
        case .jobRole: return !code.trimmingCharacters(in: .whitespaces).isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .contractor: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .engagement: return contractorID != nil && (workplaces.isEmpty || workplaceID != nil) && !details.trimmingCharacters(in: .whitespaces).isEmpty
        case .assignment: return employeeID != nil && (departmentID != nil || jobRoleID != nil || engagementID != nil)
        default: return false
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical).padding(14).novaControlBackground(cornerRadius: 14)
    }
    private func picker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) { ForEach(values, id: \.self) { Text($0).tag($0) } }
            .pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func picker<T: Identifiable>(_ title: String, selection: Binding<UUID?>, values: [T],
                                         optional: Bool = false) -> some View where T.ID == UUID {
        Picker(title, selection: selection) {
            if optional { Text(RDLocalization.string("localizable.isg.workspace.personnel.screen.secilmedi.57149c4c", table: .localizable, fallback: "Seçilmedi")).tag(UUID?.none) }
            ForEach(values) { value in Text(displayName(value)).tag(Optional(value.id)) }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func displayName<T>(_ value: T) -> String {
        if let value = value as? IsgWorkspaceDirectoryEntry { return value.name }
        if let value = value as? IsgWorkspaceEmployeeEntry { return value.name }
        if let value = value as? IsgWorkspaceAdvancedRecord { return value.title }
        return RDLocalization.string("localizable.isg.workspace.personnel.screen.kayit.a5467d32", table: .localizable, fallback: "Kayıt")
    }
    private func save() {
        let action: String
        switch route.section {
        case .jobRole: action = "job_role_save"
        case .contractor: action = "contractor_save"
        case .engagement: action = "engagement_create"
        default: action = "assignment_create"
        }
        mutate(action: action)
    }
    private func mutate(action: String) {
        var payload: [String: IsgWorkspaceRPCValue] = [
            "action": .string(action), "id": .id(route.entry?.id),
            "expected_version": .number(Int(route.entry?.version ?? 0))
        ]
        switch action {
        case "job_role_save":
            payload.merge(["code": .string(code), "name": .string(name), "description": .string(details)]) { _, new in new }
        case "contractor_save":
            payload.merge(["name": .string(name), "relation_kind": .string(relation),
                "tax_identifier": .string(taxIdentifier), "contact_name": .string(contactName),
                "contact_value": .string(contactValue)]) { _, new in new }
        case "engagement_create":
            payload.merge(["contractor_id": .id(contractorID), "workplace_id": .id(workplaceID),
                "scope": .string(details), "starts_on": .string(Self.day(startsOn)), "ends_before": .null]) { _, new in new }
        case "engagement_end": payload["ends_before"] = .string(Self.day(endsOn))
        case "assignment_create":
            payload.merge(["employee_id": .id(employeeID), "department_id": .id(departmentID),
                "job_role_id": .id(jobRoleID), "engagement_id": .id(engagementID),
                "effective_from": .string(Self.day(startsOn)), "effective_before": .null]) { _, new in new }
        case "assignment_end": payload["effective_before"] = .string(Self.day(endsOn))
        default: break
        }
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "personnel.advanced.\(action)", payload: payload)
        mutationAttempt = attempt; working = true; error = nil
        Task { @MainActor in
            do {
                try await store.mutatePersonnelAdvanced(mutationID: mutationID, payload: payload)
                celebrate(NovaSuccessMessage.recordSaved(route.section.title)); onDone()
            } catch { self.error = "İşlem tamamlanamadı. Kapsam, tarih ve sürüm bilgilerini kontrol edin." }
            working = false
        }
    }
    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
    private var minimumEndDate: Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startsOn) ?? startsOn
    }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value + "T00:00:00Z")
    }
}
