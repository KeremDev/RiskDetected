import SwiftUI

private enum IsgPersonnelSection: String, CaseIterable, Identifiable {
    case employee, workplace, department
    var id: String { rawValue }
    var title: String {
        switch self {
        case .employee: return RDLocalization.string("localizable.nova.workspace.personnel.employees", table: .localizable, fallback: "Personel")
        case .workplace: return RDLocalization.string("localizable.nova.workspace.personnel.workplaces", table: .localizable, fallback: "İşyerleri")
        case .department: return RDLocalization.string("localizable.nova.workspace.personnel.departments", table: .localizable, fallback: "Departmanlar")
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

struct IsgWorkspacePersonnelScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let companyName: String
    let canOperate: Bool
    let canManageDirectory: Bool
    let onBack: () -> Void
    @State private var section: IsgPersonnelSection = .employee
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var departments: [IsgWorkspaceDirectoryEntry] = []
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var metrics: IsgPersonnelMetrics?
    @State private var directoryRoute: IsgDirectoryRoute?
    @State private var employeeRoute: IsgEmployeeRoute?
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: IsgWorkspaceDomain.personnel.title, onBack: onBack)
                    NovaHelpHint(text: String(format: RDLocalization.string(
                        "localizable.nova.workspace.domain.scope", table: .localizable,
                        fallback: "%@ firmasına ait yetkili OSGB kayıtları gösteriliyor."), companyName))
                    if let metrics {
                        HStack(spacing: 8) {
                            NovaListStat(title: IsgPersonnelSection.employee.title, symbol: "person.2",
                                         value: String(metrics.employees.active))
                            NovaListStat(title: IsgPersonnelSection.workplace.title, symbol: "building.2",
                                         value: String(metrics.workplaces.active))
                            NovaListStat(title: IsgPersonnelSection.department.title, symbol: "square.grid.2x2",
                                         value: String(metrics.departments.active))
                        }
                    }
                    Picker("", selection: $section) {
                        ForEach(IsgPersonnelSection.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    searchField
                    if canAdd {
                        NovaCompactActionButton(title: addTitle, symbol: "plus", prominent: true) { openCreate() }
                    }
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
                                table: .localizable, fallback: "Kayıt ekleyerek firmanın personel organizasyonunu güvenli biçimde yönetin."))
                    } else { records }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }.refreshable { revision = UUID() }
        }
        .task(id: revision) { await load() }
        .novaPopup(item: $directoryRoute, onDismiss: { revision = UUID() }) { route in
            IsgWorkspaceDirectoryEditor(store: store, route: route, workplaces: workplaces) { directoryRoute = nil }
        }
        .novaPopup(item: $employeeRoute, onDismiss: { revision = UUID() }) { route in
            IsgWorkspaceEmployeeEditor(store: store, route: route, departments: departments) { employeeRoute = nil }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField(RDLocalization.string("localizable.nova.workspace.domain.search", table: .localizable,
                fallback: "Kayıtlarda ara"), text: $query).font(NovaFont.font(.body))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel(RDLocalization.string(
                        "localizable.nova.nonconformity.search.clear", table: .localizable, fallback: "Aramayı temizle"))
            }
        }.padding(.horizontal, 12).frame(minHeight: 48).novaControlBackground(cornerRadius: 16)
    }

    @ViewBuilder private var records: some View {
        switch section {
        case .employee:
            ForEach(employees.filter { matches($0.code, $0.name) }) { row in
                rowButton(title: row.name, subtitle: row.code, symbol: "person") {
                    employeeRoute = .init(entry: row)
                }
            }
        case .workplace:
            ForEach(workplaces.filter { matches($0.code, $0.name) }) { row in
                rowButton(title: row.name, subtitle: row.code, symbol: "building.2") {
                    directoryRoute = .init(kind: .workplace, entry: row)
                }
            }
        case .department:
            ForEach(departments.filter { matches($0.code, $0.name) }) { row in
                rowButton(title: row.name, subtitle: row.code, symbol: "square.grid.2x2") {
                    directoryRoute = .init(kind: .department, entry: row)
                }
            }
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
        }.buttonStyle(.plain)
    }

    private var visibleCount: Int {
        switch section {
        case .employee: return employees.filter { matches($0.code, $0.name) }.count
        case .workplace: return workplaces.filter { matches($0.code, $0.name) }.count
        case .department: return departments.filter { matches($0.code, $0.name) }.count
        }
    }
    private var canAdd: Bool { section == .employee ? canOperate : canManageDirectory }
    private var addTitle: String { String(format: RDLocalization.string(
        "localizable.nova.workspace.personnel.add", table: .localizable, fallback: "%@ ekle"), section.title) }
    private func matches(_ values: String...) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
    private func openCreate() {
        switch section {
        case .employee: employeeRoute = .init(entry: nil)
        case .workplace: directoryRoute = .init(kind: .workplace, entry: nil)
        case .department: directoryRoute = .init(kind: .department, entry: nil)
        }
    }
    @MainActor private func load() async {
        loading = true; error = nil
        do {
            async let workplaceRows = store.directory(.workplace)
            async let departmentRows = store.directory(.department)
            async let employeeRows = store.employees()
            async let metricRows = store.personnelMetrics()
            (workplaces, departments, employees, metrics) = try await
                (workplaceRows, departmentRows, employeeRows, metricRows)
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
                if route.kind == .department {
                    Picker(IsgPersonnelSection.workplace.title, selection: $workplaceID) {
                        ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                }
                if let error { NovaHelpHint(text: error) }
                NovaCompactActionButton(title: saveTitle, symbol: "checkmark", prominent: true,
                    enabled: !working && !code.trimmingCharacters(in: .whitespaces).isEmpty &&
                        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
                        (route.kind == .workplace || workplaceID != nil)) { save() }
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
        table: .localizable, fallback: "%@ ekle"), route.kind == .workplace ? IsgPersonnelSection.workplace.title : IsgPersonnelSection.department.title) }
    private var editTitle: String { RDLocalization.string("localizable.nova.workspace.personnel.edit", table: .localizable, fallback: "Kaydı düzenle") }
    private var saveTitle: String { working ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…") : RDLocalization.string("localizable.nova.editor.kaydet.8f6f32fd", table: .localizable, fallback: "Kaydet") }
    private func save() { mutate(route.entry == nil ? "create" : "edit") }
    private func archive() { mutate("archive") }
    private func mutate(_ action: String) {
        working = true; error = nil
        Task { @MainActor in
            do {
                try await store.mutateDirectory(mutationID: UUID(), kind: route.kind, action: action,
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
    @State private var working = false
    @State private var error: String?
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
                        Text(RDLocalization.string("localizable.nova.workspace.personnel.department.none", table: .localizable, fallback: "Departman seçilmedi")).tag(UUID?.none)
                        ForEach(departments) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                }
                DatePicker(RDLocalization.string("localizable.nova.workspace.personnel.hired", table: .localizable, fallback: "İşe giriş"), selection: $hiredOn, displayedComponents: .date).padding(12).novaControlBackground(cornerRadius: 14)
                Toggle(RDLocalization.string("localizable.nova.workspace.personnel.has.end", table: .localizable, fallback: "Bitiş tarihi var"), isOn: $hasEnd).padding(12).novaControlBackground(cornerRadius: 14)
                if hasEnd { DatePicker(RDLocalization.string("localizable.nova.workspace.personnel.ends", table: .localizable, fallback: "Bitiş"), selection: $endsBefore, in: hiredOn..., displayedComponents: .date).padding(12).novaControlBackground(cornerRadius: 14) }
                if let error { NovaHelpHint(text: error) }
                NovaCompactActionButton(title: working ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…") : RDLocalization.string("localizable.nova.editor.kaydet.8f6f32fd", table: .localizable, fallback: "Kaydet"), symbol: "checkmark", prominent: true, enabled: !working && !code.isEmpty && !name.isEmpty) { mutate(route.entry == nil ? "create" : "edit") }
                if route.entry != nil { NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.personnel.archive", table: .localizable, fallback: "Arşivle"), symbol: "archivebox", enabled: !working) { mutate("archive") } }
            }.padding(18).novaPopupContentSize()
        }
    }
    private func mutate(_ action: String) {
        working = true; error = nil
        Task { @MainActor in
            do {
                try await store.mutateEmployee(mutationID: UUID(), action: action, employeeID: route.entry?.id,
                    expectedVersion: route.entry?.version ?? 0, code: code, name: name, departmentID: departmentID,
                    hiredOn: action == "archive" ? nil : Self.day(hiredOn), endsBefore: action == "archive" || !hasEnd ? nil : Self.day(endsBefore))
                celebrate(action == "archive" ? NovaSuccessMessage.personnelArchived : (route.entry == nil ? NovaSuccessMessage.personnelCreated : NovaSuccessMessage.personnelUpdated))
                onDone()
            } catch { self.error = RDLocalization.string("localizable.nova.workspace.mutation.failed", table: .localizable, fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.") }
            working = false
        }
    }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
}
